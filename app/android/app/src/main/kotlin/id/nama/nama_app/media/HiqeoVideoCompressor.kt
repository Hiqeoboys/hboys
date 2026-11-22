package id.nama.nama_app.media

import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Kompresor video H.264/MP4 berbasis Android SDK murni (MediaExtractor + MediaCodec + EGL14/GLES20 + MediaMuxer).
 * Menurunkan skala secara proporsional hingga [maxHeight] (720p/1080p) serta menyesuaikan bitrate secara adaptif
 * agar hasil MP4 tetap tajam namun aman di bawah batas unggah proxy R2 ([maxBytes]).
 */
object HiqeoVideoCompressor {
    private const val TIMEOUT_US = 10_000L
    private const val FRAME_WAIT_TIMEOUT_MS = 3_000L
    private const val DEFAULT_AUDIO_BITRATE_BPS = 128_000
    private const val DEFAULT_FRAME_RATE = 30
    private const val EGL_RECORDABLE_ANDROID = 0x3142

    fun compressVideo(
        cacheDir: File,
        sourcePath: String,
        maxHeight: Int,
        bitrateBps: Int,
        maxBytes: Int,
    ): String? {
        val srcFile = File(sourcePath)
        if (!srcFile.exists() || srcFile.length() <= 0L) return null

        val meta = readMetadata(sourcePath) ?: return null
        if (meta.width <= 0 || meta.height <= 0) return null

        val safeMaxHeight = maxHeight.coerceIn(360, 2160)
        val safeMaxLongSide = (safeMaxHeight * 16f / 9f).roundToInt()
        val shortSide = min(meta.width, meta.height)
        val longSide = max(meta.width, meta.height)

        val scale = min(
            1.0,
            min(
                safeMaxHeight.toDouble() / shortSide.toDouble(),
                safeMaxLongSide.toDouble() / longSide.toDouble(),
            ),
        )

        val outWidth = makeEven((meta.width * scale).roundToInt()).coerceAtLeast(16)
        val outHeight = makeEven((meta.height * scale).roundToInt()).coerceAtLeast(16)

        val inspectExtractor = MediaExtractor()
        var videoTrackIndex = -1
        var audioTrackIndex = -1
        var videoFormat: MediaFormat? = null
        var audioFormat: MediaFormat? = null
        try {
            inspectExtractor.setDataSource(sourcePath)
            for (i in 0 until inspectExtractor.trackCount) {
                val fmt = inspectExtractor.getTrackFormat(i)
                val mime = fmt.getString(MediaFormat.KEY_MIME) ?: continue
                if (videoTrackIndex < 0 && mime.startsWith("video/")) {
                    videoTrackIndex = i
                    videoFormat = fmt
                } else if (audioTrackIndex < 0 && mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    audioFormat = fmt
                }
            }
        } catch (_: Throwable) {
            return null
        } finally {
            try {
                inspectExtractor.release()
            } catch (_: Throwable) {
            }
        }

        val srcVideoFormat = videoFormat ?: return null
        val videoMime = srcVideoFormat.getString(MediaFormat.KEY_MIME) ?: return null

        val audioBitrate = audioFormat?.let { fmt ->
            if (fmt.containsKey(MediaFormat.KEY_BIT_RATE)) {
                fmt.getInteger(MediaFormat.KEY_BIT_RATE).coerceIn(32_000, 320_000)
            } else {
                DEFAULT_AUDIO_BITRATE_BPS
            }
        } ?: 0

        val srcLength = srcFile.length()
        val isMp4File = sourcePath.endsWith(".mp4", ignoreCase = true)
        val isAvc = videoMime.equals(MediaFormat.MIMETYPE_VIDEO_AVC, ignoreCase = true)
        val withinBitrate = meta.bitrate <= 0 || meta.bitrate <= (bitrateBps * 1.15).roundToInt()

        // Fast-path passthrough jika sudah MP4 H.264 yang ringkas dan tidak melebihi batas ukuran/resolusi.
        if (isMp4File && isAvc && scale >= 0.999 && srcLength <= maxBytes.toLong() && withinBitrate) {
            return sourcePath
        }

        // Hitung anggaran bitrate adaptif agar klip berdurasi panjang tetap aman di bawah maxBytes.
        val targetTotalBytes = (maxBytes * 0.90).toLong()
        val effectiveVideoBitrate = if (meta.durationMs > 0L) {
            val maxTotalBps = (targetTotalBytes * 8L * 1000L) / meta.durationMs
            val budgetVideoBps = (maxTotalBps - audioBitrate).coerceAtLeast(300_000L)
            min(bitrateBps.toLong(), budgetVideoBps).toInt().coerceAtLeast(300_000)
        } else {
            bitrateBps.coerceAtLeast(400_000)
        }

        val frameRate = if (srcVideoFormat.containsKey(MediaFormat.KEY_FRAME_RATE)) {
            srcVideoFormat.getInteger(MediaFormat.KEY_FRAME_RATE).coerceIn(15, 60)
        } else {
            DEFAULT_FRAME_RATE
        }

        val rotation = when {
            meta.rotation != 0 -> meta.rotation
            srcVideoFormat.containsKey(MediaFormat.KEY_ROTATION) ->
                srcVideoFormat.getInteger(MediaFormat.KEY_ROTATION)
            else -> 0
        }

        val outFile = File(cacheDir, "hiqeo_vid_${System.currentTimeMillis()}.mp4")
        if (outFile.exists()) outFile.delete()

        val success = transcode(
            sourcePath = sourcePath,
            outFile = outFile,
            videoTrackIndex = videoTrackIndex,
            audioTrackIndex = audioTrackIndex,
            videoMime = videoMime,
            srcVideoFormat = srcVideoFormat,
            audioFormat = audioFormat,
            outWidth = outWidth,
            outHeight = outHeight,
            targetBitrateBps = effectiveVideoBitrate,
            frameRate = frameRate,
            rotationDegrees = rotation,
        )

        if (!success || !outFile.exists() || outFile.length() <= 0L || outFile.length() > maxBytes.toLong()) {
            if (outFile.exists()) {
                outFile.delete()
            }
            return null
        }

        return outFile.absolutePath
    }

    private fun transcode(
        sourcePath: String,
        outFile: File,
        videoTrackIndex: Int,
        audioTrackIndex: Int,
        videoMime: String,
        srcVideoFormat: MediaFormat,
        audioFormat: MediaFormat?,
        outWidth: Int,
        outHeight: Int,
        targetBitrateBps: Int,
        frameRate: Int,
        rotationDegrees: Int,
    ): Boolean {
        var videoExtractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var muxer: MediaMuxer? = null
        var eglState: EglInputSurface? = null
        var frameRenderer: TextureFrameRenderer? = null
        var surfaceTexture: SurfaceTexture? = null
        var decoderSurface: Surface? = null
        var frameThread: HandlerThread? = null

        var muxerStarted = false

        try {
            val encFormat = MediaFormat.createVideoFormat(
                MediaFormat.MIMETYPE_VIDEO_AVC,
                outWidth,
                outHeight,
            ).apply {
                setInteger(
                    MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
                )
                setInteger(MediaFormat.KEY_BIT_RATE, targetBitrateBps)
                setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            }

            encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            encoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            val encoderInputSurface = encoder.createInputSurface()
            eglState = EglInputSurface(encoderInputSurface)
            eglState.makeCurrent()
            encoder.start()

            frameRenderer = TextureFrameRenderer()
            frameThread = HandlerThread("HiqeoVideoFrameSync").apply { start() }
            val frameSync = FrameSync()
            surfaceTexture = SurfaceTexture(frameRenderer.textureId).apply {
                setOnFrameAvailableListener(
                    { frameSync.markAvailable() },
                    Handler(frameThread.looper),
                )
            }
            decoderSurface = Surface(surfaceTexture)

            val decFormat = cloneFormatWithoutRotation(srcVideoFormat)
            decoder = MediaCodec.createDecoderByType(videoMime)
            decoder.configure(decFormat, decoderSurface, null, 0)
            decoder.start()

            videoExtractor = MediaExtractor().apply {
                setDataSource(sourcePath)
                selectTrack(videoTrackIndex)
            }

            if (audioTrackIndex >= 0 && audioFormat != null) {
                audioExtractor = MediaExtractor().apply {
                    setDataSource(sourcePath)
                    selectTrack(audioTrackIndex)
                }
            }

            muxer = MediaMuxer(outFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            if (rotationDegrees != 0) {
                muxer.setOrientationHint(rotationDegrees)
            }

            var muxerVideoTrack = -1
            var muxerAudioTrack = -1
            var audioEos = audioExtractor == null

            val decoderInfo = MediaCodec.BufferInfo()
            val encoderInfo = MediaCodec.BufferInfo()
            val audioInfo = MediaCodec.BufferInfo()
            val audioBuffer = if (audioExtractor != null) ByteBuffer.allocateDirect(256 * 1024) else null
            val stMatrix = FloatArray(16)

            var extractorDone = false
            var decoderDone = false
            var encoderDone = false
            var lastVideoPtsUs = -1L
            val lastAudioPtsUsRef = longArrayOf(0L)

            while (!encoderDone) {
                // 1. Suplai sampel terkompresi dari sumber ke video decoder.
                if (!extractorDone) {
                    val inIndex = decoder.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val inBuffer = decoder.getInputBuffer(inIndex)
                        if (inBuffer != null) {
                            val sampleSize = videoExtractor.readSampleData(inBuffer, 0)
                            if (sampleSize < 0) {
                                decoder.queueInputBuffer(
                                    inIndex,
                                    0,
                                    0,
                                    0L,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                extractorDone = true
                            } else {
                                val ptsUs = videoExtractor.sampleTime.coerceAtLeast(0L)
                                val flags = videoExtractor.sampleFlags
                                decoder.queueInputBuffer(inIndex, 0, sampleSize, ptsUs, flags)
                                videoExtractor.advance()
                            }
                        }
                    }
                }

                // 2. Render frame decoder ke GL surface terenkoder sesuai skala target.
                if (!decoderDone) {
                    val decOutIndex = decoder.dequeueOutputBuffer(decoderInfo, TIMEOUT_US)
                    if (decOutIndex >= 0) {
                        val doRender = decoderInfo.size > 0 &&
                            (decoderInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0
                        decoder.releaseOutputBuffer(decOutIndex, doRender)

                        if (doRender && frameSync.awaitNewImage(FRAME_WAIT_TIMEOUT_MS)) {
                            surfaceTexture.updateTexImage()
                            surfaceTexture.getTransformMatrix(stMatrix)
                            frameRenderer.draw(stMatrix, outWidth, outHeight)
                            val ptsNs = decoderInfo.presentationTimeUs.coerceAtLeast(0L) * 1000L
                            eglState.setPresentationTime(ptsNs)
                            eglState.swapBuffers()
                        }

                        if ((decoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                            encoder.signalEndOfInputStream()
                            decoderDone = true
                        }
                    }
                }

                // 3. Tulis paket terenkode H.264 beserta audio passthrough ke MediaMuxer.
                while (true) {
                    val encTimeout = if (decoderDone) TIMEOUT_US else 0L
                    val encOutIndex = encoder.dequeueOutputBuffer(encoderInfo, encTimeout)
                    when {
                        encOutIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> break
                        encOutIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                            if (!muxerStarted) {
                                muxerVideoTrack = muxer.addTrack(encoder.outputFormat)
                                if (audioFormat != null && audioExtractor != null) {
                                    muxerAudioTrack = try {
                                        muxer.addTrack(audioFormat)
                                    } catch (_: Throwable) {
                                        audioEos = true
                                        -1
                                    }
                                }
                                muxer.start()
                                muxerStarted = true
                            }
                        }
                        encOutIndex >= 0 -> {
                            val outBuf = encoder.getOutputBuffer(encOutIndex)
                            val isConfig = (encoderInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0
                            if (outBuf != null && encoderInfo.size > 0 && !isConfig && muxerStarted) {
                                outBuf.position(encoderInfo.offset)
                                outBuf.limit(encoderInfo.offset + encoderInfo.size)
                                val safePts = if (encoderInfo.presentationTimeUs <= lastVideoPtsUs) {
                                    lastVideoPtsUs + 1L
                                } else {
                                    encoderInfo.presentationTimeUs
                                }
                                encoderInfo.presentationTimeUs = safePts
                                lastVideoPtsUs = safePts
                                muxer.writeSampleData(muxerVideoTrack, outBuf, encoderInfo)

                                if (!audioEos && muxerAudioTrack >= 0 && audioExtractor != null && audioBuffer != null) {
                                    audioEos = pumpAudioUntil(
                                        audioExtractor = audioExtractor,
                                        muxer = muxer,
                                        audioTrack = muxerAudioTrack,
                                        buffer = audioBuffer,
                                        info = audioInfo,
                                        targetPtsUs = safePts,
                                        lastAudioPtsUsRef = lastAudioPtsUsRef,
                                    )
                                }
                            }
                            encoder.releaseOutputBuffer(encOutIndex, false)
                            if ((encoderInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                encoderDone = true
                                break
                            }
                        }
                    }
                }
            }

            if (muxerStarted && !audioEos && muxerAudioTrack >= 0 && audioExtractor != null && audioBuffer != null) {
                pumpAudioUntil(
                    audioExtractor = audioExtractor,
                    muxer = muxer,
                    audioTrack = muxerAudioTrack,
                    buffer = audioBuffer,
                    info = audioInfo,
                    targetPtsUs = Long.MAX_VALUE,
                    lastAudioPtsUsRef = lastAudioPtsUsRef,
                )
            }

            return muxerStarted
        } catch (_: Throwable) {
            return false
        } finally {
            try {
                decoder?.stop()
            } catch (_: Throwable) {
            }
            try {
                decoder?.release()
            } catch (_: Throwable) {
            }
            try {
                decoderSurface?.release()
            } catch (_: Throwable) {
            }
            try {
                surfaceTexture?.release()
            } catch (_: Throwable) {
            }
            try {
                frameThread?.quitSafely()
            } catch (_: Throwable) {
            }
            try {
                frameRenderer?.release()
            } catch (_: Throwable) {
            }
            try {
                encoder?.stop()
            } catch (_: Throwable) {
            }
            try {
                encoder?.release()
            } catch (_: Throwable) {
            }
            try {
                eglState?.release()
            } catch (_: Throwable) {
            }
            try {
                videoExtractor?.release()
            } catch (_: Throwable) {
            }
            try {
                audioExtractor?.release()
            } catch (_: Throwable) {
            }
            if (muxerStarted) {
                try {
                    muxer?.stop()
                } catch (_: Throwable) {
                }
            }
            try {
                muxer?.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun pumpAudioUntil(
        audioExtractor: MediaExtractor,
        muxer: MediaMuxer,
        audioTrack: Int,
        buffer: ByteBuffer,
        info: MediaCodec.BufferInfo,
        targetPtsUs: Long,
        lastAudioPtsUsRef: LongArray,
    ): Boolean {
        while (true) {
            val pts = audioExtractor.sampleTime
            if (pts < 0L) return true
            if (pts > targetPtsUs) return false

            buffer.clear()
            val sampleSize = audioExtractor.readSampleData(buffer, 0)
            if (sampleSize < 0) return true

            val safePts = max(pts, lastAudioPtsUsRef[0])
            lastAudioPtsUsRef[0] = safePts

            buffer.position(0)
            buffer.limit(sampleSize)
            info.set(
                0,
                sampleSize,
                safePts,
                audioExtractor.sampleFlags,
            )
            muxer.writeSampleData(audioTrack, buffer, info)
            if (!audioExtractor.advance()) return true
        }
    }

    private fun cloneFormatWithoutRotation(src: MediaFormat): MediaFormat {
        val copy = MediaFormat.createVideoFormat(
            src.getString(MediaFormat.KEY_MIME) ?: MediaFormat.MIMETYPE_VIDEO_AVC,
            src.getInteger(MediaFormat.KEY_WIDTH),
            src.getInteger(MediaFormat.KEY_HEIGHT),
        )
        copyIntIfPresent(src, copy, MediaFormat.KEY_MAX_INPUT_SIZE)
        copyIntIfPresent(src, copy, MediaFormat.KEY_FRAME_RATE)
        copyIntIfPresent(src, copy, MediaFormat.KEY_COLOR_FORMAT)
        copyLongIfPresent(src, copy, MediaFormat.KEY_DURATION)
        copyByteBufferIfPresent(src, copy, "csd-0")
        copyByteBufferIfPresent(src, copy, "csd-1")
        // Nolkan rotasi agar decoder merender frame mentah tanpa transformasi ganda dari vendor HAL.
        copy.setInteger(MediaFormat.KEY_ROTATION, 0)
        return copy
    }

    private fun copyIntIfPresent(src: MediaFormat, dst: MediaFormat, key: String) {
        if (src.containsKey(key)) {
            dst.setInteger(key, src.getInteger(key))
        }
    }

    private fun copyLongIfPresent(src: MediaFormat, dst: MediaFormat, key: String) {
        if (src.containsKey(key)) {
            dst.setLong(key, src.getLong(key))
        }
    }

    private fun copyByteBufferIfPresent(src: MediaFormat, dst: MediaFormat, key: String) {
        if (src.containsKey(key)) {
            val bb = src.getByteBuffer(key) ?: return
            val clone = ByteBuffer.allocateDirect(bb.remaining())
            clone.put(bb.duplicate())
            clone.flip()
            dst.setByteBuffer(key, clone)
        }
    }

    private fun readMetadata(sourcePath: String): VideoMeta? {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(sourcePath)
            val width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull() ?: 0
            val height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull() ?: 0
            val rotation = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val bitrate = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)?.toIntOrNull() ?: 0
            val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
            VideoMeta(width, height, rotation, bitrate, durationMs)
        } catch (_: Throwable) {
            null
        } finally {
            try {
                retriever.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun makeEven(value: Int): Int = (value / 2) * 2

    private data class VideoMeta(
        val width: Int,
        val height: Int,
        val rotation: Int,
        val bitrate: Int,
        val durationMs: Long,
    )

    private class FrameSync {
        private val lock = ReentrantLock()
        private val condition = lock.newCondition()
        private var available = false

        fun markAvailable() {
            lock.withLock {
                available = true
                condition.signalAll()
            }
        }

        fun awaitNewImage(timeoutMs: Long): Boolean {
            lock.withLock {
                val deadlineNs = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMs)
                while (!available) {
                    val remainingNs = deadlineNs - System.nanoTime()
                    if (remainingNs <= 0L) return false
                    condition.awaitNanos(remainingNs)
                }
                available = false
                return true
            }
        }
    }

    private class EglInputSurface(private var surface: Surface?) {
        private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
        private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
        private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

        init {
            eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (eglDisplay === EGL14.EGL_NO_DISPLAY) {
                throw IllegalStateException("Unable to get EGL14 display")
            }
            val version = IntArray(2)
            if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
                throw IllegalStateException("Unable to initialize EGL14")
            }

            val attribList = intArrayOf(
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL_RECORDABLE_ANDROID, 1,
                EGL14.EGL_NONE,
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val numConfigs = IntArray(1)
            if (!EGL14.eglChooseConfig(eglDisplay, attribList, 0, configs, 0, configs.size, numConfigs, 0) ||
                numConfigs[0] <= 0 || configs[0] == null
            ) {
                throw IllegalStateException("Unable to choose RGB888+recordable EGLConfig")
            }

            val contextAttribs = intArrayOf(
                EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
                EGL14.EGL_NONE,
            )
            eglContext = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
            checkEglError("eglCreateContext")

            val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
            eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, configs[0], surface, surfaceAttribs, 0)
            checkEglError("eglCreateWindowSurface")
        }

        fun makeCurrent() {
            if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
                throw IllegalStateException("eglMakeCurrent failed")
            }
        }

        fun setPresentationTime(nsecs: Long) {
            EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, nsecs)
        }

        fun swapBuffers(): Boolean = EGL14.eglSwapBuffers(eglDisplay, eglSurface)

        fun release() {
            if (eglDisplay !== EGL14.EGL_NO_DISPLAY) {
                EGL14.eglMakeCurrent(
                    eglDisplay,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_SURFACE,
                    EGL14.EGL_NO_CONTEXT,
                )
                if (eglSurface !== EGL14.EGL_NO_SURFACE) {
                    EGL14.eglDestroySurface(eglDisplay, eglSurface)
                }
                if (eglContext !== EGL14.EGL_NO_CONTEXT) {
                    EGL14.eglDestroyContext(eglDisplay, eglContext)
                }
                EGL14.eglReleaseThread()
                EGL14.eglTerminate(eglDisplay)
            }
            surface?.release()
            surface = null
            eglDisplay = EGL14.EGL_NO_DISPLAY
            eglContext = EGL14.EGL_NO_CONTEXT
            eglSurface = EGL14.EGL_NO_SURFACE
        }

        private fun checkEglError(op: String) {
            val error = EGL14.eglGetError()
            if (error != EGL14.EGL_SUCCESS) {
                throw IllegalStateException("$op: EGL error 0x${Integer.toHexString(error)}")
            }
        }
    }

    private class TextureFrameRenderer {
        private val triangleVerticesData = floatArrayOf(
            -1.0f, -1.0f, 0.0f, 0.0f, 0.0f,
             1.0f, -1.0f, 0.0f, 1.0f, 0.0f,
            -1.0f,  1.0f, 0.0f, 0.0f, 1.0f,
             1.0f,  1.0f, 0.0f, 1.0f, 1.0f,
        )
        private val vertices: FloatBuffer = ByteBuffer
            .allocateDirect(triangleVerticesData.size * 4)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply {
                put(triangleVerticesData)
                position(0)
            }

        private val mvpMatrix = FloatArray(16).apply { Matrix.setIdentityM(this, 0) }
        private var program = 0
        private var mvpMatrixHandle = 0
        private var stMatrixHandle = 0
        private var positionHandle = 0
        private var texCoordHandle = 0
        var textureId: Int = 0
            private set

        init {
            program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            positionHandle = GLES20.glGetAttribLocation(program, "aPosition")
            texCoordHandle = GLES20.glGetAttribLocation(program, "aTextureCoord")
            mvpMatrixHandle = GLES20.glGetUniformLocation(program, "uMVPMatrix")
            stMatrixHandle = GLES20.glGetUniformLocation(program, "uSTMatrix")

            val textures = IntArray(1)
            GLES20.glGenTextures(1, textures, 0)
            textureId = textures[0]
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
            GLES20.glTexParameterf(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_MIN_FILTER,
                GLES20.GL_LINEAR.toFloat(),
            )
            GLES20.glTexParameterf(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_MAG_FILTER,
                GLES20.GL_LINEAR.toFloat(),
            )
            GLES20.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_WRAP_S,
                GLES20.GL_CLAMP_TO_EDGE,
            )
            GLES20.glTexParameteri(
                GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
                GLES20.GL_TEXTURE_WRAP_T,
                GLES20.GL_CLAMP_TO_EDGE,
            )
        }

        fun draw(stMatrix: FloatArray, width: Int, height: Int) {
            GLES20.glViewport(0, 0, width, height)
            GLES20.glClearColor(0.0f, 0.0f, 0.0f, 1.0f)
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            GLES20.glUseProgram(program)

            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)

            vertices.position(0)
            GLES20.glVertexAttribPointer(positionHandle, 3, GLES20.GL_FLOAT, false, 20, vertices)
            GLES20.glEnableVertexAttribArray(positionHandle)

            vertices.position(3)
            GLES20.glVertexAttribPointer(texCoordHandle, 2, GLES20.GL_FLOAT, false, 20, vertices)
            GLES20.glEnableVertexAttribArray(texCoordHandle)

            GLES20.glUniformMatrix4fv(mvpMatrixHandle, 1, false, mvpMatrix, 0)
            GLES20.glUniformMatrix4fv(stMatrixHandle, 1, false, stMatrix, 0)

            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GLES20.glFinish()
        }

        fun release() {
            if (program != 0) {
                GLES20.glDeleteProgram(program)
                program = 0
            }
            if (textureId != 0) {
                GLES20.glDeleteTextures(1, intArrayOf(textureId), 0)
                textureId = 0
            }
        }

        private fun loadShader(shaderType: Int, source: String): Int {
            val shader = GLES20.glCreateShader(shaderType)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val compiled = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
            if (compiled[0] == 0) {
                val info = GLES20.glGetShaderInfoLog(shader)
                GLES20.glDeleteShader(shader)
                throw IllegalStateException("Shader compile error: $info")
            }
            return shader
        }

        private fun createProgram(vertexSource: String, fragmentSource: String): Int {
            val vertexShader = loadShader(GLES20.GL_VERTEX_SHADER, vertexSource)
            val fragmentShader = loadShader(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
            val prog = GLES20.glCreateProgram()
            GLES20.glAttachShader(prog, vertexShader)
            GLES20.glAttachShader(prog, fragmentShader)
            GLES20.glLinkProgram(prog)
            val linkStatus = IntArray(1)
            GLES20.glGetProgramiv(prog, GLES20.GL_LINK_STATUS, linkStatus, 0)
            if (linkStatus[0] != GLES20.GL_TRUE) {
                val info = GLES20.glGetProgramInfoLog(prog)
                GLES20.glDeleteProgram(prog)
                throw IllegalStateException("Program link error: $info")
            }
            GLES20.glDeleteShader(vertexShader)
            GLES20.glDeleteShader(fragmentShader)
            return prog
        }

        companion object {
            private const val VERTEX_SHADER =
                """
                uniform mat4 uMVPMatrix;
                uniform mat4 uSTMatrix;
                attribute vec4 aPosition;
                attribute vec4 aTextureCoord;
                varying vec2 vTextureCoord;
                void main() {
                    gl_Position = uMVPMatrix * aPosition;
                    vTextureCoord = (uSTMatrix * aTextureCoord).xy;
                }
                """

            private const val FRAGMENT_SHADER =
                """
                #extension GL_OES_EGL_image_external : require
                precision mediump float;
                varying vec2 vTextureCoord;
                uniform samplerExternalOES sTexture;
                void main() {
                    gl_FragColor = texture2D(sTexture, vTextureCoord);
                }
                """
        }
    }
}
