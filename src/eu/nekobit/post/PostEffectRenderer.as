package eu.nekobit.post
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	
	import eu.nekobit.core.CameraOverlay;
	import eu.nekobit.post.effects.PostEffect;
	
	import flash.display.Stage3D;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;

	/**
	 * The PostRenderer class is used to render post-processing effects such as MappedGlow, OuterGlow and DepthOfField.
	 * 
	 * @author Varnius
	 */
	public class PostEffectRenderer
	{
		/**
		 * Associated Stage3D instance.
		 */
		public var stage3D:Stage3D;
		
		private var effects:Dictionary = new Dictionary();
		
		/**
		 * Creates a new instance of PostEffectRenderer. 
		 * 
		 * @param stage3D Associated Stage3D instance.
		 */
		public function PostEffectRenderer(stage3D:Stage3D)
		{
			this.stage3D = stage3D;
		}
		
		/*---------------------------
		Public methods
		---------------------------*/
		
		/**
		 * Applies an effect to specified camera.
		 * 
		 * @param camera Camera that will have the effects attached.
		 * @param effect Effect to add.
		 */
		public function addEffect(camera:Camera3D, effect:PostEffect):void
		{
			var curr:PostEffect = effects[camera];
			var overlay:CameraOverlay;
			
			// List is not created yet
			if(curr == null)
			{
				effects[camera] = effect;
				
				// Apply camera overlay
				camera.addChild(effect.overlay);
				effect.upload(stage3D.context3D);
			}
			// Add to the end of the list if list exists
			else 
			{
				while(curr.next != null)
				{
					curr = curr.next;
				}
				
				curr.next = effect;
				camera.addChild(effect.overlay);
				effect.upload(stage3D.context3D);
			}
		}
		
		/**
		 * Removes single effect from the camera.
		 * 
		 * @param camera Target camera.
		 * @param effect Effect to remove.
		 */		
		public function removeEffect(camera:Camera3D, effect:PostEffect):void
		{
			var curr:PostEffect = effects[camera];
			var prev:PostEffect = curr;
						
			while(curr != null)
			{
				if(curr == effect)
				{
					if(prev == curr)
					{
						effects[camera] = curr.next;
						camera.removeChild(curr.overlay);
						curr.dispose();
					}
					else
					{
						prev.next = curr.next;
						camera.removeChild(curr.overlay);
						curr.dispose();
					}
				}
				
				prev = curr;
				curr = curr.next;
			}
		}
		
		/**
		 * Removes all effects from the camera.
		 * 
		 * @param camera Target camera.
		 */		
		public function removeAllEffects(camera:Camera3D):void
		{		
			var curr:PostEffect = effects[camera];
							
			while(curr != null)
			{
				curr.dispose();
				camera.removeChild(curr.overlay);
				curr = curr.next;
			}
			
			effects[camera] = null;
		}
		
		/**
		 * Updates single effect.
		 * 
		 * @param camera Target camera.
		 * @param effect Effect to update.
		 */		
		public function updateSingleEffect(camera:Camera3D, effect:PostEffect):void			
		{
			var curr:PostEffect = effects[camera];
			
			while(curr != null)
			{
				if(curr == effect)
				{
					hideOverlays();
					curr.update(stage3D, camera);
					showOverlays();
					break;
				}
				
				curr = curr.next;
			}
		}
		
		/**
		 * Updates all effects attached to the camera.
		 * 
		 * @param camera Target camera.
		 */		
		public function updateAllEffects(camera:Camera3D):void			
		{
			var curr:PostEffect = effects[camera];
			
			while(curr != null)
			{
				hideOverlays();
				curr.update(stage3D, camera);
				showOverlays();
				curr = curr.next;
			}
		}
		
		/*----------------------
		Helpers
		----------------------*/
		
		private function showOverlays():void
		{
			for each(var curr:PostEffect in effects)
			{				
				while(curr != null)
				{
					curr.overlay.visible = true;
					curr = curr.next;
				}
			}
		}
		
		private function hideOverlays():void
		{
			for each(var curr:PostEffect in effects)
			{				
				while(curr != null)
				{
					curr.overlay.visible = false;
					curr = curr.next;
				}
			}
		}
	}
}