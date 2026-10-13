package dev.sbcraft.client;

import com.mojang.blaze3d.buffers.GpuBuffer;
import com.mojang.blaze3d.opengl.GlStateManager;
import com.mojang.blaze3d.opengl.GlTexture;
import com.mojang.blaze3d.textures.GpuTexture;
import dev.sbcraft.client.mixin.GlBufferAccessor;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL30;

/**
 * Reads a depth texture into a GPU buffer (asynchronously, as a pixel-pack readback).
 *
 * <p>Minecraft 26.1.2's {@code GlCommandEncoder.copyTextureToBuffer} always attaches the source as a colour
 * attachment, so a depth texture leaves the read framebuffer incomplete (GL_INVALID_FRAMEBUFFER_OPERATION). This
 * attaches it as the depth attachment of a framebuffer of our own instead. Render thread only.
 */
final class DepthReadback {
	private static final int GL_READ_FRAMEBUFFER = 0x8CA8;
	private static final int GL_PIXEL_PACK_BUFFER = 0x88EB;
	private static int fbo;

	private DepthReadback() {
	}

	static void copy(final GpuTexture depth, final GpuBuffer into, final int w, final int h) {
		if (fbo == 0) {
			fbo = GL30.glGenFramebuffers();
		}

		GlStateManager.clearGlErrors();
		GlStateManager._glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
		GL30.glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL30.GL_DEPTH_ATTACHMENT, GL11.GL_TEXTURE_2D, ((GlTexture) depth).glId(), 0);
		GL11.glReadBuffer(GL11.GL_NONE);
		GlStateManager._glBindBuffer(GL_PIXEL_PACK_BUFFER, ((GlBufferAccessor) into).sbcraft$handle());
		GlStateManager._pixelStore(GL11.GL_PACK_ALIGNMENT, 4);
		GlStateManager._readPixels(0, 0, w, h, GL11.GL_DEPTH_COMPONENT, GL11.GL_FLOAT, 0L);
		GL30.glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL30.GL_DEPTH_ATTACHMENT, GL11.GL_TEXTURE_2D, 0, 0);
		GlStateManager._glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
		GlStateManager._glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
		int error = GlStateManager._getError();
		if (error != 0) {
			throw new IllegalStateException("depth readback failed: GL error " + error);
		}
	}
}
