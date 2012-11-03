package eu.nekobit.alternativa3d.post.effects
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.materials.compiler.Procedure;
	
	import com.adobe.utils.AGALMacroAssembler;
	
	import eu.nekobit.alternativa3d.post.EffectBlendMode;
	
	import flash.display.Stage3D;
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.Context3DVertexBufferFormat;
	import flash.display3D.Program3D;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;
	
	/**
	 * Depth of field post effect.
	 */
	public class Waves extends PostEffect
	{
		// Cache	
		private static var programCache:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;
		private var finalProgram:Program3D;
		
		private var hOffset:Number;
		private var vOffset:Number;
		
		private var prevPrerenderTexWidth:int = 0;
		private var prevPrerenderTexHeight:int = 0;
		private var constant:Vector.<Number> = new <Number>[0, 0, 0, 0];
		
		public var frequencyX:Number = 30;
		public var frequencyY:Number = 20;
		public var amount:Number = 0.2
		
		public function Waves()
		{
			blendMode = EffectBlendMode.NONE;
			overlay.effect = this;
			needsOverlay = false;
			needsScene = true;
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
					
					finalProgram = getFinalProgram();					
					
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
			
			// Set constants			
			constant[0] = frequencyX;
			constant[1] = frequencyY;	
			constant[2] = 5;
			constant[3] = amount;
			 			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, constant, 1);	
			
			constant[0] = postRenderer.prerenderTextureWidth;
			constant[1] = postRenderer.prerenderTextureHeight;
			
			cachedContext3D.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 1, constant, 1);	
			
			// Set samplers
			cachedContext3D.setTextureAt(0, postRenderer.cachedScene);
		
			// Set program
			cachedContext3D.setProgram(finalProgram);			
			
			// Render final scene
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
		
		[Embed(source="macro/Swirl.macro", mimeType="application/octet-stream")]
		protected const ShaderMacro:Class;
		
		private function getFinalProgram():Program3D
		{
			var vertexAssembler:AGALMacroAssembler = new AGALMacroAssembler();
			var fragmentAssembler:AGALMacroAssembler = new AGALMacroAssembler();			
			var shaderSplit:Array = String(new ShaderMacro).split("####");
			
			vertexAssembler.assemble(Context3DProgramType.VERTEX, shaderSplit[0]);
			fragmentAssembler.assemble(Context3DProgramType.FRAGMENT, shaderSplit[1]);
			
			var program:Program3D = cachedContext3D.createProgram();
			program.upload(vertexAssembler.agalcode, fragmentAssembler.agalcode);
						
			return program;
		}
	}
}