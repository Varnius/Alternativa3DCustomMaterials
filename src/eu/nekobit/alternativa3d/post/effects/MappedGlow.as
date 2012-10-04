package eu.nekobit.alternativa3d.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.Renderer;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import eu.nekobit.alternativa3d.core.renderers.MappedGlowRenderer;
	import eu.nekobit.alternativa3d.materials.MappedGlowMaterial;
	import eu.nekobit.alternativa3d.post.EffectBlendMode;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
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
		// Program cache
		private static var programCache:Dictionary = new Dictionary(true);	
		private var cachedContext3D:Context3D;		
		private var blurProgram:ShaderProgram;	
		
		private var prevPrerenderTexWidth:int = 0;
		private var prevPrerenderTexHeight:int = 0;
		private var glowRenderer:MappedGlowRenderer = new MappedGlowRenderer();
		private var hOffset:Number;
		private var vOffset:Number;		
		
		// Texture offsets for blur shader
		private var textureOffsets:Vector.<Number> = new <Number>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		
		// Convolution kernel values
		private var convValues:Vector.<Number> = new <Number>[0.125, 0.125, 0.125, 0.125];
		
		// Render targets for internal rendering		
		alternativa3d var glowRenderTarget1:Texture;
		alternativa3d var glowRenderTarget2:Texture;
		
		/**
		 * Horizontal glow amount
		 */
		public var glowX:Number = 1.0;
		
		/**
		 * Vertical glow amount
		 */
		public var glowY:Number = 1.0;	
		
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
				glowRenderTarget1 = stage3D.context3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				glowRenderTarget2 = stage3D.context3D.createTexture(prerenderTextureWidth, prerenderTextureHeight, Context3DTextureFormat.BGRA, true);
				
				hOffset = 1 / prerenderTextureWidth;
				vOffset = 1 / prerenderTextureHeight;
				
				prevPrerenderTexWidth = prerenderTextureWidth;
				prevPrerenderTexHeight = prerenderTextureHeight;
			}		
			
			// Render all glow sources to texture
			stage3D.context3D.setRenderToTexture(glowRenderTarget1, true);
			stage3D.context3D.clear(0, 0, 0, 0);
			
			// Use custom renderer to draw only objects that use GlowMaterial
			var oldRenderer:Renderer = camera.renderer;	
			var oldAlpha:Number = camera.view.backgroundAlpha;
			camera.renderer = glowRenderer;
			camera.view.backgroundAlpha = 0;
			
			MappedGlowMaterial.glowRenderPass = true;
			camera.render(stage3D);
			MappedGlowMaterial.glowRenderPass = false;
			
			camera.renderer = oldRenderer;
			camera.view.backgroundAlpha = oldAlpha;
			stage3D.context3D.setRenderToBackBuffer();			
			
			/*-------------------
			Horizontal glow 
			render pass
			-------------------*/ 
			
			var i:int;
			var currRenderTarget:Texture = glowRenderTarget2;
			var currRenderSource:Texture = glowRenderTarget1;
			
			textureOffsets[0]  = -3 * hOffset * glowX;
			textureOffsets[4]  = -2 * hOffset * glowX;
			textureOffsets[8]  =     -hOffset * glowX;
			textureOffsets[12] =  0;
			textureOffsets[16] =      hOffset * glowX;
			textureOffsets[20] =  2 * hOffset * glowX;
			textureOffsets[24] =  3 * hOffset * glowX;
			
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
			
			// Render intermediate blur result
			cachedContext3D.setRenderToTexture(currRenderTarget);
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
			
			// Reset texture offsets
			textureOffsets[0]  = 0;
			textureOffsets[4]  = 0;
			textureOffsets[8]  = 0;
			textureOffsets[12] = 0;
			textureOffsets[16] = 0;
			textureOffsets[20] = 0;
			textureOffsets[24] = 0;	
			
			/*-------------------
			Vertical glow 
			render pass
			-------------------*/			
			
			textureOffsets[1]  = -3 * vOffset * glowY;
			textureOffsets[5]  = -2 * vOffset * glowY;
			textureOffsets[9]  =     -vOffset * glowY;
			textureOffsets[13] =  0;
			textureOffsets[17] =      vOffset * glowY;
			textureOffsets[21] =  2 * vOffset * glowY;
			textureOffsets[25] =  3 * vOffset * glowY;
			
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
			
			// Render intermediate blur result
			cachedContext3D.setRenderToTexture(currRenderTarget);
			
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
			
			textureOffsets[1] = 0;
			textureOffsets[5] = 0;
			textureOffsets[9] = 0;
			textureOffsets[13] = 0;
			textureOffsets[17] = 0;
			textureOffsets[21] = 0;
			textureOffsets[25] = 0;	
			
			// Clean up
			cachedContext3D.setTextureAt(0, null);
			cachedContext3D.setVertexBufferAt(0, null);
			cachedContext3D.setVertexBufferAt(1, null);
			
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
			
			vertexLinker.addProcedure(blurVertexProcedure);
			fragmentLinker.addProcedure(blurFragmentProcedure);
			fragmentLinker.varyings = vertexLinker.varyings;
			
			return new ShaderProgram(vertexLinker, fragmentLinker);
		}
		
		/*---------------------------
		Blur shaders
		---------------------------*/
		
		static alternativa3d const blurVertexProcedure:Procedure = new Procedure(
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
			//"#c7=cUVOffset7",
			"#v0=vUV0",
			"#v1=vUV1",
			"#v2=vUV2",
			"#v3=vUV3",
			"#v4=vUV4",
			"#v5=vUV5",
			"#v6=vUV6",
			//"#v7=vUV7",
			
			// Add texture offsets, move to varyings
			"add v0 a1 c0",
			"add v1 a1 c1",
			"add v2 a1 c2",
			"add v3 a1 c3",
			"add v4 a1 c4",
			"add v5 a1 c5",
			"add v6 a1 c6",
			//"add v7 a1 c7",
			
			// Set vertex position as output
			"mov o0 a0"
		], "vertexProcedure");
		
		static alternativa3d const blurFragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sDiffuseMap",
			"#c0=cConvolutionVals1",
			"#c1=cConvolutionVals2",
			"#v0=vUV0",
			"#v1=vUV1",
			"#v2=vUV2",
			"#v3=vUV3",
			"#v4=vUV4",
			"#v5=vUV5",
			"#v6=vUV6",
			//"#v7=vUV7",
			
			// Apply convolution kernel
			
			"tex t0,v0,s0 <2d,clamp,linear>",
			"tex t1,v1,s0 <2d,clamp,linear>",
			"mul t0 t0 c0.x",
			"mul t1 t1 c0.y",
			"add t0 t0 t1",
			
			"tex t1,v2,s0 <2d,clamp,linear>",
			"tex t2,v3,s0 <2d,clamp,linear>",
			"mul t1 t1 c0.z",
			"mul t2 t2 c0.w",
			"add t0 t0 t1",
			"add t0 t0 t2",
			
			"tex t1,v4,s0 <2d,clamp,linear>",
			"tex t2,v5,s0 <2d,clamp,linear>",
			"mul t1 t1 c1.x",
			"mul t2 t2 c1.y",
			"add t0 t0 t1",
			"add t0 t0 t2",
			
			"tex t1,v6,s0 <2d,clamp,linear>",
			//"tex t2,v7,s0 <2d,clamp,linear>",
			"mul t1 t1 c1.z",
			//"mul t2 t2 c1.w",
			"add t0 t0 t1",
			//"add t0 t0 t2",
			
			"mov o0 t0",
		], "fragmentProcedure");
	}
}