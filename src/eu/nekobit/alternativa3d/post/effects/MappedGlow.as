package eu.nekobit.alternativa3d.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.Renderer;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import eu.nekobit.alternativa3d.core.cameras.RenderToTextureCamera;
	import eu.nekobit.alternativa3d.core.renderers.MappedGlowRenderer;
	import eu.nekobit.alternativa3d.materials.MappedGlowMaterial;
	import eu.nekobit.alternativa3d.post.EffectBlendMode;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;
	
	/**
	 * Mapped glow effect. Takes all objects with assigned MappedGlowMaterial and applies glow to them.
	 * 
	 * @author Varnius
	 */
	public class MappedGlow extends PostEffect
	{
		// Cache	
		private static var programCache:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;		
		private var blurProgram:ShaderProgram;		
		
		private var prevPrerenderTexWidth:int = 0;
		private var prevPrerenderTexHeight:int = 0;
		private var glowRenderer:MappedGlowRenderer = new MappedGlowRenderer();
		private var hOffset:Number;
		private var vOffset:Number;
		private var prerenderCamera:RenderToTextureCamera = new RenderToTextureCamera(1, 10);
		
		// Texture offsets for convolution shader
		private var textureOffsets:Vector.<Number> = new <Number>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		
		// Convolution kernel values
		private var convValues:Vector.<Number> = new <Number>[0.125, 0.125, 0.125, 0.125];
		
		// Render targets for internal rendering		
		alternativa3d var glowRenderTarget1:Texture;
		alternativa3d var glowRenderTarget2:Texture;
		
		/**
		 * Number of glow passes. Increases glow spread. More passes degrade performance.
		 */
		public var numGlowPasses:int = 2;
		
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
				
				var programs:Dictionary = programCache[cachedContext3D];
				
				// No programs created yet
				if(programs == null)
				{					
					programs = new Dictionary();
					programCache[cachedContext3D] = programs;
					
					blurProgram = getBlurProgram();
					blurProgram.upload(cachedContext3D);
					
					programs["BlurProgram"] = blurProgram;
				}
				else 
				{
					blurProgram = programs["BlurProgram"];
				}
				
				contextJustUpdated = true;
			}
			
			// Handle render target textures
			if(contextJustUpdated || glowRenderTarget1 == null || glowRenderTarget2 == null || prevPrerenderTexWidth != prerenderTextureWidth || prevPrerenderTexHeight != prerenderTextureHeight)
			{				
				glowRenderTarget1 = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				glowRenderTarget2 = cachedContext3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				
				hOffset = 1 / prerenderTextureWidth;
				vOffset = 1 / prerenderTextureHeight;
				
				prevPrerenderTexWidth = prerenderTextureWidth;
				prevPrerenderTexHeight = prerenderTextureHeight;
			}			
			
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
			
			/*-------------------
			Render all glow sources
			to texture
			-------------------*/	
			
			// todo: antialiasing not supported by FP
			prerenderCamera.texture = glowRenderTarget1;
			MappedGlowMaterial.glowRenderPass = true;
			prerenderCamera.render(stage3D);
			MappedGlowMaterial.glowRenderPass = false;
			
			camera.view.backgroundAlpha = oldAlpha;
			camera.view.backgroundColor = oldBGColor;
			camera.parent.removeChild(prerenderCamera);	
			
			/*-------------------
			Horizontal glow 
			render pass
			-------------------*/	 
			
			var i:int;
			var currRenderTarget:Texture = glowRenderTarget2;
			var currRenderSource:Texture = glowRenderTarget1;
			
			//todo: + half texel as in directX?			
			/*textureOffsets[0] = -4 * hOffset;
			textureOffsets[4] = -3 * hOffset;
			textureOffsets[8] = -2 * hOffset;
			textureOffsets[12] =     -hOffset;
			textureOffsets[16] =      hOffset;
			textureOffsets[20] =  2 * hOffset;
			textureOffsets[24] =  3 * hOffset;
			textureOffsets[28] =  4 * hOffset;*/
			
			textureOffsets[0]  = -hOffset;
			textureOffsets[4]  = -hOffset;
			textureOffsets[8]  = -hOffset;
			textureOffsets[12] =     0;
			textureOffsets[16] =     0;
			textureOffsets[20] =  hOffset;
			textureOffsets[24] =  hOffset;
			textureOffsets[28] =  hOffset;
			
			textureOffsets[1]  =  vOffset;
			textureOffsets[5]  =  0;
			textureOffsets[9]  = -vOffset;
			textureOffsets[13] =  vOffset;
			textureOffsets[17] = -vOffset;
			textureOffsets[21] =  vOffset;
			textureOffsets[25] =  0;
			textureOffsets[29] = -vOffset;
			
			for(i = 0; i < numGlowPasses; i++)
			{
				// Set attributes
				cachedContext3D.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
				cachedContext3D.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);				
				
				// Set constants 
				cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, textureOffsets, 8);
				cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, convValues, 1);
				
				// Set samplers
				cachedContext3D.setTextureAt(0, currRenderSource);
				
				// Set program
				cachedContext3D.setProgram(blurProgram.program);
				
				// Render intermediate convolution result
				cachedContext3D.setRenderToTexture(currRenderTarget);
				cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
				cachedContext3D.clear(0,0,0,0);
				cachedContext3D.drawTriangles(overlayIndexBuffer);			
				cachedContext3D.present();
				
				if(currRenderTarget == glowRenderTarget2)
				{
					currRenderTarget = glowRenderTarget1;
					currRenderSource = glowRenderTarget2;
				} else {
					currRenderTarget = glowRenderTarget2;
					currRenderSource = glowRenderTarget1;
				}
			}
			
			// Reset texture offsets
			textureOffsets[0]  = 0;
			textureOffsets[4]  = 0;
			textureOffsets[8]  = 0;
			textureOffsets[12] = 0;
			textureOffsets[16] = 0;
			textureOffsets[20] = 0;
			textureOffsets[24] = 0;
			textureOffsets[28] = 0;
			
			textureOffsets[1] = 0;
			textureOffsets[5] = 0;
			textureOffsets[9] = 0;
			textureOffsets[13] = 0;
			textureOffsets[17] =  0;
			textureOffsets[21] =  0;
			textureOffsets[25] =  0;
			textureOffsets[29] =  0;
			
			/*-------------------
			Vertical glow 
			render pass
			-------------------*/			
			
			/*textureOffsets[1]  = -4 * vOffset;
			textureOffsets[5]  = -3 * vOffset;
			textureOffsets[9]  = -2 * vOffset;
			textureOffsets[13] =     -vOffset;
			textureOffsets[17] =      vOffset;
			textureOffsets[21] =  2 * vOffset;
			textureOffsets[25] =  3 * vOffset;
			textureOffsets[29] =  4 * vOffset;*/
			
			/*textureOffsets[0] = -hOffset;
			textureOffsets[4] = -hOffset;
			textureOffsets[8] = -hOffset;
			textureOffsets[12] =     0;
			textureOffsets[16] =     0;
			textureOffsets[20] =  hOffset;
			textureOffsets[24] =  hOffset;
			textureOffsets[28] =  hOffset;
			
			textureOffsets[1] = vOffset;
			textureOffsets[5] = 0;
			textureOffsets[9] = -vOffset;
			textureOffsets[13] =     vOffset;
			textureOffsets[17] =     -vOffset;
			textureOffsets[21] =  vOffset;
			textureOffsets[25] =  0;
			textureOffsets[29] =  -vOffset;
			
			for(i = 0; i < numGlowPasses; i++)
			{
			// Set attributes
			stage3D.context3D.setVertexBufferAt(0, overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			stage3D.context3D.setVertexBufferAt(1, overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);			
			
			// Set constants 
			stage3D.context3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, textureOffsets, 8);
			stage3D.context3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, convValues, 1);
			
			// Set samplers
			stage3D.context3D.setTextureAt(0, currRenderSource);
			
			// Set program
			stage3D.context3D.setProgram(convolutionProgram.program);
			
			// Render intermediate convolution result
			stage3D.context3D.setRenderToTexture(currRenderTarget);
			
			stage3D.context3D.clear(0,0,0,0);
			stage3D.context3D.drawTriangles(overlayIndexBuffer);			
			stage3D.context3D.present();
			
			if(currRenderTarget == glowRenderTarget2)
			{
			currRenderTarget = glowRenderTarget1;
			currRenderSource = glowRenderTarget2;
			} else {
			currRenderTarget = glowRenderTarget2;
			currRenderSource = glowRenderTarget1;
			}
			}*/
			
			// Reset texture offsets
			/*textureOffsets[0]  = 0;
			textureOffsets[4]  = 0;
			textureOffsets[8]  = 0;
			textureOffsets[12] = 0;
			textureOffsets[16] = 0;
			textureOffsets[20] = 0;
			textureOffsets[24] = 0;
			textureOffsets[28] = 0;
			
			textureOffsets[1] = 0;
			textureOffsets[5] = 0;
			textureOffsets[9] = 0;
			textureOffsets[13] = 0;
			textureOffsets[17] =     0;
			textureOffsets[21] =  0;
			textureOffsets[25] =  0;
			textureOffsets[29] =  0;*/
			
			// Clean up
			cachedContext3D.setTextureAt(0, null);
			stage3D.context3D.setVertexBufferAt(0, null);
			stage3D.context3D.setVertexBufferAt(1, null);
			
			// Pass changes to overlay
			overlay.diffuseMap = glowRenderTarget1;
			overlay.blendAmount = blendAmount;
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function dispose():void
		{
			if(glowRenderTarget1)
			{
				glowRenderTarget1.dispose();
				glowRenderTarget2.dispose();
			}
		}
		
		/*---------------------------
		Helpers
		---------------------------*/
		
		private function getBlurProgram():ShaderProgram
		{
			var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);
			
			vertexLinker.addProcedure(convolutionVertexProcedure);
			fragmentLinker.addProcedure(convolutionFragmentProcedure);
			fragmentLinker.varyings = vertexLinker.varyings;
			
			return new ShaderProgram(vertexLinker, fragmentLinker);
		}
		
		/*---------------------------
		Convolution procedures
		---------------------------*/
		
		static alternativa3d const convolutionVertexProcedure:Procedure = new Procedure(
			[
				// Declarations
				"#a0=aPosition",			
				"#a1=aUV",
				"#c0=cUVOffset0",
				"#c1=cUVOffset1",
				"#c2=cUVOffset2",
				"#c3=cUVOffset3",
				"#c4=cUVOffset4",
				"#c5=cUVOffset5",
				"#c6=cUVOffset6",
				"#c7=cUVOffset7",
				"#v0=vUV0",
				"#v1=vUV1",
				"#v2=vUV2",
				"#v3=vUV3",
				"#v4=vUV4",
				"#v5=vUV5",
				"#v6=vUV6",
				"#v7=vUV7",
				
				// Add texture offsets, move to varyings
				"add v0 a1 c0",
				"add v1 a1 c1",
				"add v2 a1 c2",
				"add v3 a1 c3",
				"add v4 a1 c4",
				"add v5 a1 c5",
				"add v6 a1 c6",
				"add v7 a1 c7",
				
				// Set vertex position as output
				"mov o0 a0"
			], "vertexProcedure");
		
		static alternativa3d const convolutionFragmentProcedure:Procedure = new Procedure(
			[
				// Declarations
				"#s0=sDiffuseMap",
				"#c0=cConvolution",
				"#v0=vUV0",
				"#v1=vUV1",
				"#v2=vUV2",
				"#v3=vUV3",
				"#v4=vUV4",
				"#v5=vUV5",
				"#v6=vUV6",
				"#v7=vUV7",
				
				// Apply convolution kernel
				
				"tex t0,v0,s0 <2d,clamp,linear>",
				"tex t1,v1,s0 <2d,clamp,linear>",
				"mul t0 t0 c0",
				"mul t1 t1 c0",
				"add t0 t0 t1",
				
				"tex t1,v2,s0 <2d,clamp,linear>",
				"tex t2,v3,s0 <2d,clamp,linear>",
				"mul t1 t1 c0",
				"mul t2 t2 c0",
				"add t0 t0 t1",
				"add t0 t0 t2",
				
				"tex t1,v4,s0 <2d,clamp,linear>",
				"tex t2,v5,s0 <2d,clamp,linear>",
				"mul t1 t1 c0",
				"mul t2 t2 c0",
				"add t0 t0 t1",
				"add t0 t0 t2",
				
				"tex t1,v6,s0 <2d,clamp,linear>",
				"tex t2,v7,s0 <2d,clamp,linear>",
				"mul t1 t1 c0",
				"mul t2 t2 c0",
				"add t0 t0 t1",
				"add t0 t0 t2",
				
				"mov o0 t0",
			], "fragmentProcedure");
	}
}