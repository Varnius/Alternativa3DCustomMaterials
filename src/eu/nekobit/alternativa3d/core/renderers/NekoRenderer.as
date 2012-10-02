package eu.nekobit.alternativa3d.core.renderers
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.DrawUnit;
	import alternativa.engine3d.core.Renderer;
	
	import flash.display3D.Context3D;
	import flash.display3D.Context3DCompareMode;
	
	use namespace alternativa3d;
	
	/**
	 * Should be swapped with regular camera renderer when rendering post effects such as Depth-of-Field and others.
	 */
	public class NekoRenderer extends Renderer
	{
		public static const SKY:int = 10;
		
		public static const OPAQUE:int = 20;
		
		public static const OPAQUE_OVERHEAD:int = 25;
		
		public static const DECALS:int = 30;
		
		public static const TRANSPARENT_SORT:int = 40;
		
		public static const NEXT_LAYER:int = 50;
		
		public static const NEKO_POST_OVERLAY:int = 60;		
		
		public function NekoRenderer()
		{
			super();			
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function render(context3D:Context3D):void
		{
			updateContext3D(context3D);		
			
			var drawUnitsLength:int = drawUnits.length;
			
			for(var i:int = 0; i < drawUnitsLength; i++)
			{
				var list:DrawUnit = drawUnits[i];
				
				if(list != null)
				{
					switch(i)
					{
						case SKY:
							context3D.setDepthTest(false, Context3DCompareMode.ALWAYS);
							break;
						case OPAQUE:
							context3D.setDepthTest(true, Context3DCompareMode.LESS);
							break;
						case OPAQUE_OVERHEAD:
							context3D.setDepthTest(false, Context3DCompareMode.EQUAL);
							break;
						case DECALS:
							context3D.setDepthTest(false, Context3DCompareMode.LESS_EQUAL);
							break;
						case TRANSPARENT_SORT:
							if(list.next != null)
								list = sortByAverageZ(list);
							context3D.setDepthTest(false, Context3DCompareMode.LESS);
							break;
						case NEXT_LAYER:
							context3D.setDepthTest(false, Context3DCompareMode.ALWAYS);
							break;
						case NEKO_POST_OVERLAY:
							context3D.setDepthTest(false, Context3DCompareMode.ALWAYS);
							break;
					}
					
					// Rendering
					while(list != null)
					{
						var next:DrawUnit = list.next;
						
						renderDrawUnit(list, context3D, camera);
						// Send to collector
						list.clear();
						list.next = collector;
						collector = list;
						list = next;
					}
				}
			}
			
			// TODO: not free buffers and textures in each renderer, only when full camera cycle finishes.
			freeContext3DProperties(context3D);
			
			// Clear
			drawUnits.length = 0;
		}
		
		/**
		 * @inherit
		 */
		override alternativa3d function addDrawUnit(drawUnit:DrawUnit, renderPriority:int):void
		{
			// Increase array of priorities, if it is necessary
			if(renderPriority >= drawUnits.length)
			{
				drawUnits.length = renderPriority + 1;
			}
			
			// Add to the end of the list
			
			var curr:DrawUnit = drawUnits[renderPriority];
			
			if(curr != null)
			{
				while(curr.next != null)
				{					
					curr = curr.next;
				}
				
				curr.next = drawUnit;
			} else {
				drawUnits[renderPriority] = drawUnit;
			}
		}
	}
}