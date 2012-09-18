package alternativa.engine3d.core
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.materials.ShaderProgram;
	
	import flash.display3D.IndexBuffer3D;
	import flash.display3D.Program3D;
	
	use namespace alternativa3d;
	
	public class FilterRenderer extends Renderer
	{
		private var dummyDrawUnit:DrawUnit = new DrawUnit();
		
		public function FilterRenderer()
		{
			super();
		}
		
		/**
		 * @private
		 */
		alternativa3d function createGlowDrawUnit(object:Object3D, program:Program3D, indexBuffer:IndexBuffer3D, firstIndex:int, numTriangles:int, debugShader:ShaderProgram = null):DrawUnit
		{
			return super.createDrawUnit(object, program, indexBuffer, firstIndex, numTriangles, debugShader);
		}
		
		/**
		 * @private
		 */
		override alternativa3d function createDrawUnit(object:Object3D, program:Program3D, indexBuffer:IndexBuffer3D, firstIndex:int, numTriangles:int, debugShader:ShaderProgram = null):DrawUnit
		{
			var res:DrawUnit = dummyDrawUnit;
			
			res.object = object;
			res.program = program;
			res.indexBuffer = indexBuffer;
			res.firstIndex = firstIndex;
			res.numTriangles = numTriangles;
			
			return res;
		}
		
		/**
		 * @private
		 */
		override alternativa3d function addDrawUnit(drawUnit:DrawUnit, renderPriority:int):void
		{
			if(drawUnit == dummyDrawUnit)
			{
				return;
			}
			
			super.addDrawUnit(drawUnit, renderPriority);
		}
	}
}