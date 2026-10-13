package dev.sbcraft.client.mixin;

import dev.sbcraft.Passthrough;
import dev.sbcraft.client.FrameExporter;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.GameRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.ModifyArg;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

/** No sky while a host is attached (the host's sky shows through), and the frame is split into world and overlay layers. */
@Mixin(GameRenderer.class)
abstract class GameRendererMixin {
	@ModifyArg(
		method = "renderLevel",
		at = @At(value = "INVOKE", target = "Lnet/minecraft/client/renderer/LevelRenderer;renderLevel(Lcom/mojang/blaze3d/resource/GraphicsResourceAllocator;Lnet/minecraft/client/DeltaTracker;ZLnet/minecraft/client/renderer/state/level/CameraRenderState;Lorg/joml/Matrix4fc;Lcom/mojang/blaze3d/buffers/GpuBufferSlice;Lorg/joml/Vector4f;ZLnet/minecraft/client/renderer/chunk/ChunkSectionsToRender;)V"),
		index = 7
	)
	private boolean passthrough$noSky(final boolean shouldRenderSky) {
		return shouldRenderSky && !Passthrough.active;
	}

	@Inject(
		method = "renderLevel",
		// right after the level: 26.1.2 clears the depth texture before the hand is drawn
		at = @At(value = "INVOKE", target = "Lnet/minecraft/client/renderer/LevelRenderer;renderLevel(Lcom/mojang/blaze3d/resource/GraphicsResourceAllocator;Lnet/minecraft/client/DeltaTracker;ZLnet/minecraft/client/renderer/state/level/CameraRenderState;Lorg/joml/Matrix4fc;Lcom/mojang/blaze3d/buffers/GpuBufferSlice;Lorg/joml/Vector4f;ZLnet/minecraft/client/renderer/chunk/ChunkSectionsToRender;)V", shift = At.Shift.AFTER)
	)
	private void passthrough$captureWorld(final CallbackInfo ci) {
		FrameExporter.captureWorld(Minecraft.getInstance().getMainRenderTarget());
	}

	@Inject(method = "render", at = @At("TAIL"))
	private void passthrough$captureOverlay(final CallbackInfo ci) {
		FrameExporter.captureOverlay(Minecraft.getInstance().getMainRenderTarget());
	}
}
