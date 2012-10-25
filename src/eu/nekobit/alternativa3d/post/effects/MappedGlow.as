package eu.nekobit.alternativa3d.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	
	import eu.nekobit.alternativa3d.core.cameras.RenderToTextureCamera;
	import eu.nekobit.alternativa3d.core.renderers.MappedGlowRenderer;
	import eu.nekobit.alternativa3d.materials.MappedGlowMaterial;
	import eu.nekobit.alternativa3d.post.EffectBlendMode;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.textures.Texture;
	
	use namespace alternativa3d;
	
	/**
	 * Mapped glow effect. Takes all objects with assigned MappedGlowMaterial and applies glow to them.
	 * 
	 * @author Varnius
	 */
	public class MappedGlow extends BlurBase
	{
		// Cache
		private var cachedContext3D:Context3D;	
		
		private var prevPrerenderTexWidth:int = 0;
		private var prevPrerenderTexHeight:int = 0;
		private var glowRenderer:MappedGlowRenderer = new MappedGlowRenderer();
		private var prerenderCamera:RenderToTextureCamera = new RenderToTextureCamera(1, 10);	
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget1:Texture;
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget2:Texture;
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget3:Texture;
		
		/**
		 * @private
		 */
		alternativa3d var renderTarget4:Texture;
		
		/**
		 * Glow blending amount.
		 */
		public var blendAmount:Number = 1.0;
		
		/**
		 * Creates a new instance of this effect.
		 */
		public function MappedGlow()
		{
			blendMode = EffectBlendMode.ADD;
			prerenderCamera.renderer = glowRenderer;
			blurX = blurY = 0.5;
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function update(stage3D:Stage3D, camera:Camera3D):void
		{
			super.update(stage3D, camera);
			
			if(camera == null || stage3D == null)
			{
				return;
			}
			
			/*-------------------
			Update cache
			-------------------*/
			
			var contextJustUpdated:Boolean = false;
			
			if(stage3D.context3D != cachedContext3D)
			{
				cachedContext3D = stage3D.context3D;				
				contextJustUpdated = true;
			}
			
			// Handle render target textures
			if(contextJustUpdated || renderTarget1 == null || renderTarget2 == null || prevPrerenderTexWidth != prerenderTextureWidth || prevPrerenderTexHeight != prerenderTextureHeight)
			{				
				renderTarget1 = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				renderTarget2 = cachedContext3D.createTexture(prerenderTextureWidth / 2, prerenderTextureHeight / 2, Context3DTextureFormat.BGRA, true);
				renderTarget3 = cachedContext3D.createTexture(prerenderTextureWidth / 4, prerenderTextureHeight / 4, Context3DTextureFormat.BGRA, true);
				renderTarget4 = cachedContext3D.createTexture(prerenderTextureWidth / 4, prerenderTextureHeight / 4, Context3DTextureFormat.BGRA, true);
				
				prevPrerenderTexWidth = prerenderTextureWidth;
				prevPrerenderTexHeight = prerenderTextureHeight;
			}	
			
			/*-------------------
			Render all glow
			sources to texture
			-------------------*/
			
			prerenderCamera.setPosition(camera.x, camera.y, camera.z);			
			prerenderCamera.rotationX = camera.rotationX;
			prerenderCamera.rotationY = camera.rotationY;
			prerenderCamera.rotationZ = camera.rotationZ;
			prerenderCamera.fov = camera.fov;
			prerenderCamera.nearClipping = camera.nearClipping;
			prerenderCamera.farClipping = camera.farClipping;
			prerenderCamera.orthographic = camera.orthographic;
			
			// Reuse same view
			prerenderCamera.view = camera.view;
			camera.parent.addChild(prerenderCamera);	
			
			var oldAlpha:Number = prerenderCamera.view.backgroundAlpha;
			var oldBGColor:uint = prerenderCamera.view.backgroundColor;
			prerenderCamera.view.backgroundAlpha = 0;
			prerenderCamera.view.backgroundColor = 0x000000;	
			
			// todo: antialiasing not supported by FP
			prerenderCamera.sceneRenderTarget = renderTarget1;
			MappedGlowMaterial.glowRenderPass = true;
			prerenderCamera.render(stage3D);
			MappedGlowMaterial.glowRenderPass = false;
			
			camera.view.backgroundAlpha = oldAlpha;
			camera.view.backgroundColor = oldBGColor;
			camera.parent.removeChild(prerenderCamera);	
			
			/*-------------------
			Downsample scene			
			-------------------*/		
			
			resample(renderTarget1, renderTarget2);
			resample(renderTarget2, renderTarget3);	
			
			/*-------------------
			Blur regular scene
			-------------------*/			
			
			blur(renderTarget3, renderTarget4, prerenderTextureWidth / 4, prerenderTextureHeight / 4);
			
			/*-------------------
			Upsample scene			
			-------------------*/		
			
			resample(renderTarget3, renderTarget2);
			resample(renderTarget2, renderTarget1);
			
			// Clean up
			cachedContext3D.setTextureAt(0, null);
			stage3D.context3D.setVertexBufferAt(0, null);
			stage3D.context3D.setVertexBufferAt(1, null);
			
			// Pass changes to overlay
			overlay.diffuseMap = renderTarget1;
			overlay.blendAmount = blendAmount;
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function dispose():void
		{
			if(renderTarget1)
			{
				renderTarget1.dispose();
				renderTarget2.dispose();
				renderTarget3.dispose();
				renderTarget4.dispose();
			}
		}
	}
}