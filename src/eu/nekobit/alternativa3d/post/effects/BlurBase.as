package eu.nekobit.alternativa3d.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;

	/**
	 * @private
	 * 
	 * @author Varnius
	 */
	public class BlurBase extends PostEffect
	{
		// Cache	
		private static var programCache:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;
		protected var blurProgram:ShaderProgram;
		
		// Texture offsets for blur shader
		protected var textureOffsets:Vector.<Number> = new <Number>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
		
		// Convolution kernel values for blur shader
		protected var convValues:Vector.<Number> = new <Number>[
			0.09, 0.11, 0.18, 0.24, 0.18, 0.11, 0.09, 0
		];
		
		protected var hOffset:Number;
		protected var vOffset:Number;
		protected var blurClearParamsHorizontal:Vector.<Number> = new <Number>[0, 0, 0, 1];
		protected var blurClearParamsVertical:Vector.<Number> = new <Number>[0, 0, 0, 1];
		protected var blurBlendFactors:Vector.<String> = new <String>[
			Context3DBlendFactor.ONE,
			Context3DBlendFactor.ZERO,
			Context3DBlendFactor.ONE,
			Context3DBlendFactor.ZERO
		];
		
		/**
		 * Horizontal blur amount
		 */
		public var blurX:Number = 1.0;
		
		/**
		 * Vertical blur amount
		 */
		public var blurY:Number = 1.0;
		
		public function BlurBase()
		{
			super();
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
			}
		}
		
		/**
		 * Uses two render targets to apply blur to source texture.
		 * The blur is rendered like this: source -> destination, destination -> source.
		 * 
		 * @param source First render target.
		 * @param destination Second render target.
		 * @param targetWidth The width of render targets.
		 * @param targetHeight The height of render targets.
		 * @return Render target containing final blur.
		 */
		protected function blur(source:Texture, destination:Texture, targetWidth:Number, targetHeight:Number):void
		{
			hOffset = 1 / targetWidth;
			vOffset = 1 / targetHeight;
			
			/*-------------------
			Horizontal blur pass
			-------------------*/			
			
			textureOffsets[0]  = -3 * hOffset * blurX;
			textureOffsets[4]  = -2 * hOffset * blurX;
			textureOffsets[8]  =     -hOffset * blurX;
			textureOffsets[12] =  0;
			textureOffsets[16] =      hOffset * blurX;
			textureOffsets[20] =  2 * hOffset * blurX;
			textureOffsets[24] =  3 * hOffset * blurX;		
			
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, postRenderer.overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, postRenderer.overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);				
			
			// Set constants 
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, textureOffsets, 8);
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, convValues, 2);
			
			// Set samplers
			cachedContext3D.setTextureAt(0, source);
			
			// Set program
			cachedContext3D.setProgram(blurProgram.program);
			
			// Render blur
			cachedContext3D.setRenderToTexture(destination);
			cachedContext3D.setBlendFactors(blurBlendFactors[0], blurBlendFactors[1]);
			cachedContext3D.clear(
				blurClearParamsHorizontal[0],
				blurClearParamsHorizontal[1],
				blurClearParamsHorizontal[2],
				blurClearParamsHorizontal[3]
			);
			
			cachedContext3D.drawTriangles(postRenderer.overlayIndexBuffer);			
			cachedContext3D.setRenderToBackBuffer();
			
			// Reset texture offsets
			textureOffsets[0]  = 0;
			textureOffsets[4]  = 0;
			textureOffsets[8]  = 0;
			textureOffsets[12] = 0;
			textureOffsets[16] = 0;
			textureOffsets[20] = 0;
			textureOffsets[24] = 0;
			
			/*-------------------
			Vertical blur pass
			-------------------*/
			
			textureOffsets[1]  = -3 * vOffset * blurY;
			textureOffsets[5]  = -2 * vOffset * blurY;
			textureOffsets[9]  =     -vOffset * blurY;
			textureOffsets[13] =  0;
			textureOffsets[17] =      vOffset * blurY;
			textureOffsets[21] =  2 * vOffset * blurY;
			textureOffsets[25] =  3 * vOffset * blurY;
			
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, postRenderer.overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, postRenderer.overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);
			
			// Set constants 
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, textureOffsets, 8);
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, convValues, 2);
			
			// Set samplers
			cachedContext3D.setTextureAt(0, destination);
			
			// Set program
			cachedContext3D.setProgram(blurProgram.program);
			
			// Render intermediate convolution result
			cachedContext3D.setRenderToTexture(source);
			cachedContext3D.setBlendFactors(blurBlendFactors[2], blurBlendFactors[3]);
			cachedContext3D.clear(
				blurClearParamsVertical[0],
				blurClearParamsVertical[1],
				blurClearParamsVertical[2],
				blurClearParamsVertical[3]
			);
			
			cachedContext3D.drawTriangles(postRenderer.overlayIndexBuffer);			
			cachedContext3D.setRenderToBackBuffer();
			
			textureOffsets[1] = 0;
			textureOffsets[5] = 0;
			textureOffsets[9] = 0;
			textureOffsets[13] = 0;
			textureOffsets[17] = 0;
			textureOffsets[21] = 0;
			textureOffsets[25] = 0;
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
		Blur shader program
		---------------------------*/
		
		/**
		 * @private
		 */
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
		], "BlurVertex");
		
		/**
		 * @private
		 */
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
		], "BlurFragment");
	}
}