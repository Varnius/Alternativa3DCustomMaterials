package eu.nekobit.alternativa3d.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import eu.nekobit.alternativa3d.post.EffectBlendMode;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;
	
	/**
	 * Console version of FXAA post effect. An anti-aliasing technique implemented as post effect. Finds and slightly blurs jagged edges.
	 * The console version of this shader simpler than PC version and produces less accurate results.
	 * 
	 * @author Varnius
	 */
	public class FXAAConsole extends PostEffect
	{
		// Cache	
		private static var programCache:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;
		private var finalProgram:ShaderProgram;
		
		private var prevPrerenderTexWidth:int = 0;
		private var prevPrerenderTexHeight:int = 0;
		private var constant:Vector.<Number> = new <Number>[0, 0, 0, 0];
		
		/**
		 * Sample step scale factor.
		 */
		public var sampleScaleFactor:Number = 1.0;
		
		/**
		 * FXAA_SPAN_MAX
		 */
		public var spanMax:Number = 8.0;
		
		/**
		 * FXAA_REDUCE_MUL
		 */
		public var reduceMul:Number = 1 / 8;
		
		/**
		 * FXAA_REDUCE_MIN
		 */
		public var reduceMin:Number = 1 / 128;
		
		public function FXAAConsole()
		{
			blendMode = EffectBlendMode.NONE;
			overlay.effect = this;
			needsScene = true;
			needsOverlay = false;
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function update(stage3D:Stage3D, camera:Camera3D):void
		{
			super.update(stage3D, camera);
			
			if(camera == null || stage3D == null || !_enabled)
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
					
					finalProgram = getFinalProgram();
					finalProgram.upload(cachedContext3D);					
					
					programs["FinalProgram"] = finalProgram;
				}
				else
				{
					finalProgram = programs["FinalProgram"];
				}
				
				contextJustUpdated = true;
			}		
			
			/*-------------------
			Render final view
			-------------------*/
			
			// Set attributes
			cachedContext3D.setVertexBufferAt(0, postRenderer.overlayVertexBuffer, 0, Context3DVertexBufferFormat.FLOAT_3);
			cachedContext3D.setVertexBufferAt(1, postRenderer.overlayVertexBuffer, 3, Context3DVertexBufferFormat.FLOAT_2);			
			
			var tWidth:Number = (1 / postRenderer.prerenderTextureWidth) * sampleScaleFactor;
			var tHeight:Number = (1 / postRenderer.prerenderTextureHeight) * sampleScaleFactor;
			
			// Set vertex constants 				
			constant[0] = -tWidth;
			constant[1] = tHeight;
			constant[2] = -tWidth;
			constant[3] = -tHeight;
			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, constant, 1);
			
			constant[0] = tWidth;
			constant[1] = tHeight;
			constant[2] = tWidth;
			constant[3] = -tHeight;
			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 1, constant, 1);
			
			// Set pixel constants 
			// First two are unchanged
			constant[2] = spanMax; 			// FXAA_SPAN_MAX
			constant[3] = reduceMul * 0.25; // FXAA_REDUCE_MUL * 0.25
			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, constant, 1);
			
			constant[0] = 0.299;
			constant[1]	= 0.587;
			constant[2] = 0.114;
			constant[3] = 1.0; 		// ALPHA
			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 1, constant, 1);
			
			constant[0] = reduceMin; 	// FXAA_REDUCE_MIN
			constant[1]	= -spanMax; 	// -FXAA_SPAN_MAX
			constant[2] = 0 / 3 - 0.5;
			constant[3] = 3 / 3 - 0.5;
			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 2, constant, 1);
			
			constant[0] = 1 / 2;
			constant[1]	= 1 / 3 - 0.5;
			constant[2] = 2 / 3 - 0.5;
			constant[3] = 1 / 4;
			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 3, constant, 1);
			
			// Set samplers
			cachedContext3D.setTextureAt(0, postRenderer.cachedScene);	
			
			// Set program
			cachedContext3D.setProgram(finalProgram.program);			
			
			// Combine
			cachedContext3D.setRenderToTexture(postRenderer.cachedSceneTmp);
			cachedContext3D.setBlendFactors(Context3DBlendFactor.ONE, Context3DBlendFactor.ZERO);
			cachedContext3D.clear();			
			cachedContext3D.drawTriangles(postRenderer.overlayIndexBuffer);				
			stage3D.context3D.setRenderToBackBuffer();
			
			// Clean up
			cachedContext3D.setVertexBufferAt(0, null);
			cachedContext3D.setVertexBufferAt(1, null);
			cachedContext3D.setTextureAt(0, null);
			
			// Swap render targets in postRenderer
			var tmp:Texture = postRenderer.cachedScene;
			postRenderer.cachedScene = postRenderer.cachedSceneTmp;
			postRenderer.cachedSceneTmp = tmp;
		}
		
		/*---------------------------
		Helpers
		---------------------------*/
		
		private function getFinalProgram():ShaderProgram
		{
			var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);
			
			vertexLinker.addProcedure(finalVertexProcedure);
			fragmentLinker.addProcedure(finalFragmentProcedure);
			fragmentLinker.varyings = vertexLinker.varyings;
			
			return new ShaderProgram(vertexLinker, fragmentLinker);
		}
		
		/*---------------------------
		Final render program
		---------------------------*/
		
		/**
		 * @private
		 */
		static alternativa3d const finalVertexProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#a0=aPosition",			
			"#a1=aUV",
			"#v0=vUVM",
			"#v1=vUVNE",
			"#v2=vUVNW",
			"#v3=vUVSE",
			"#v4=vUVSW",
			// - + / - -
			"#c0=cParams",
			// + + / + -
			"#c1=cParams2",
			
			"mov v0 a1",
			"add v1.xyzw a1.xyzw c0.xyzw",
			"add v2.xyzw a1.xyzw c0.zwxy",
			"add v3.xyzw a1.xyzw c1.xyzw",
			"add v4.xyzw a1.xyzw c1.zwxy",

			// Set vertex position as output
			"mov o0 a0"			
		], "FinalVertex");
		
		/**
		 * @private
		 */
		static alternativa3d const finalFragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sRegularScene",
			// tWidth, tHeight, FXAA_SPAN_MAX, FXAA_REDUCE_MUL
			"#c0=cParams",
			// LUMA-R, LUMA-G, LUMA-B, ALPHA
			"#c1=cParams2",
			// FXAA_REDUCE_MIN, -FXAA_SPAN_MAX, 0/3 -0.5, 3/3 - 0.5
			"#c2=cParams3",		
			// 0.5, 1/3 - 0.5, 2/3 - 0.5, 0.25
			"#c3=cParams4",
			"#v0=vUVM",
			"#v1=vUVNE",
			"#v2=vUVNW",
			"#v3=vUVSE",
			"#v4=vUVSW",
			
			/*------------------------------------------
			Take 5 samples		
			------------------------------------------*/
			
			// Sample middle
			"tex t0,v0,s0 <2d,clamp,linear>",
			// Sample north-west
			"tex t1,v1,s0 <2d,clamp,linear>",
			// Sample south-west
			"tex t2,v2,s0 <2d,clamp,linear>",
			// Sample north-east
			"tex t3,v3,s0 <2d,clamp,linear>",
			// Sample south-east
			"tex t4,v4,s0 <2d,clamp,linear>",
			
			/*------------------------------------------
			Calculate luma values for each sample			
			------------------------------------------*/
			
			// Luma M
			"dp3 t0.x t0.xyz c1.xyz",
			// Luma NW
			"dp3 t0.y t1.xyz c1.xyz",
			// Luma SW
			"dp3 t0.z t2.xyz c1.xyz",
			// Luma NE
			"dp3 t0.w t3.xyz c1.xyz",
			// Luma SE
			"dp3 t1.x t4.xyz c1.xyz",
			
			// t0.xyzw = M, NW, SW, NE
			// t1.x    = SE
			
			/*------------------------------------------
			Luma min/max			
			------------------------------------------*/
			
			"min t2.x t0.z t1.x",
			"min t2.y t0.y t0.w",
			"min t2.x t2.x t2.y",
			"min t2.x t2.x t0.x",
			
			"max t2.y t0.z t1.x",
			"max t2.z t0.y t0.w",
			"max t2.y t2.y t2.z",
			"max t2.y t2.y t0.x",
			
			// t2.xy = lumaMin, lumaMax
			
			/*------------------------------------------
			Calculate dir		
			------------------------------------------*/
			
			"add t3.x t0.y t0.w",
			"add t3.y t0.z t1.x",
			"sub t3.x t3.x t3.y",
			"neg t3.x t3.x",
			
			"add t3.y t0.y t0.z",
			"add t3.z t0.w t1.x",
			"sub t3.y t3.y t3.z",
			
			"mov t2.zw t3.xy",
			
			// t2.xyzw = lumaMin, lumaMax, dir.x, dir.y
			
			/*------------------------------------------
			dirReduce		
			------------------------------------------*/
			
			// Sum up lumas
			
			"mov t3.x t0.y",
			"add t3.x t3.x t0.z",
			"add t3.x t3.x t0.w",
			"add t3.x t3.x t1.x",
			
			// Multiply by FXAA_REDUCE_MUL
			"mul t3.x t3.x c0.w",
			
			// max(t3.x, FXAA_REDUCE_MIN)
			"max t3.x t3.x c2.x",
			
			// t3.x = dirReduce

			/*------------------------------------------
			rcpDirMin	
			------------------------------------------*/
			
			// todo: fixme
			"abs t4.x t2.z",
			"abs t4.y t2.w",
			"min t4.x t4.x t4.y",
			// Add dirReduce
			//"add t4.x t4.x t3.x",
			"rcp t4.x t4.x",
			"add t3.x t3.x t4.x",
			
			// t3.x = rcpDirMin
			
			/*------------------------------------------
			dir again
			------------------------------------------*/
			
			"mul t2.zwzw t2.zwzw t3.xxxx",
			"max t4.xy t2.zw c2.yy",
			"min t4.xy t4.xy c0.zz",
			"mul t3.zwzw t4.xyxy c0.xyxy",
			
			// t3 = rcpDirMin, undefined, dir.x, dir.y
			
			/*------------------------------------------
			rgbA
			------------------------------------------*/
			
			// coord 1
			"mul t4.xyxy t3.zwzw c3.yyyy",
			"add t4.xy t4.xy v0.xy",
			
			// coord 2
			// fill all t5
			"mul t5.xyzw t3.zwzw c3.zzzz",
			"add t5.xy t5.xy v0.xy",
			
			// Sample both, sum up and multiply by 0.5
			"tex t6,t4,s0 <2d,clamp,linear>",
			"tex t7,t5,s0 <2d,clamp,linear>",
			"add t6.xyz t6.xyz t7.xyz",
			"mul t6.xyz t6.xyz c3.x",
			
			// rgbA = t6.xyz
			
			/*------------------------------------------
			rgbB
			------------------------------------------*/
			
			// coord 1
			"mul t4.xyxy t3.zwzw c2.zzzz",
			"add t4.xy t4.xy v0.xy",
			
			// coord 2
			"mul t5.xyxy t3.zwzw c2.wwww",
			"add t5.xy t5.xy v0.xy",
			
			// Sample both, sum up and multiply by 0.25
			"tex t0,t4,s0 <2d,clamp,linear>",
			"tex t1,t5,s0 <2d,clamp,linear>",
			"add t0.xyz t0.xyz t1.xyz",
			"mul t0.xyz t0.xyz c3.w",
			
			// rgbA * 0.5
			"mul t1.xyz t6.xyz c3.x",
			// Final rgbB value
			"add t1.xyz t1.xyz t0.xyz",
			
			// rgbB = t1.xyz
			
			/*------------------------------------------
			Finalize
			------------------------------------------*/
			
			// lumaB
			"dp3 t0.x t1.xyz c1.xyz",
			
			// t3.x = 1 if((lumaB < lumaMin) || (lumaB > lumaMax))
			"slt t3.x t0.x t2.x",
			"slt t5.x t2.y t0.x",
			"add t3.x t3.x t5.x",
			"sat t3.x t3.x",
			
			// Amount of each
			"mul t6.xyz t6.xyz t3.x",
			"sub t4.x c1.w t3.x",
			"mul t1.xyz t1.xyz t4.x",
			"add t6.xyz t6.xyz t1.xyz",
			"mov t6.w c1.w",
			
			// Return final color
			"mov o0 t6",
		], "FinalFragment");
	}
}