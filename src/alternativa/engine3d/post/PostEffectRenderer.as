package alternativa.engine3d.post
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.CameraOverlay;
	import alternativa.engine3d.post.effects.PostEffect;
	
	import flash.display.Stage3D;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;

	/**
	 * The PostRenderer class is used to render post processing effects such as MappedGlow and OuterGlow.
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
			var curr:EffectList = effects[camera];
			var overlay:CameraOverlay;
			
			// List is not created yet
			if(curr == null)
			{
				curr = new EffectList();
				curr.effect = effect;
				effects[camera] = curr;
				
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
				
				curr.next = new EffectList();
				curr.next.effect = effect;
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
			var curr:EffectList = effects[camera];
			var prev:EffectList = curr;
						
			while(curr != null)
			{
				if(curr.effect == effect)
				{
					if(prev == curr)
					{
						effects[camera] = curr.next;
						curr.effect.dispose();
					}
					else
					{
						prev.next = curr.next;
						curr.effect.dispose();
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
			var curr:EffectList = effects[camera];
							
			while(curr != null)
			{
				curr.effect.dispose();
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
			var curr:EffectList = effects[camera];
			
			while(curr != null)
			{
				if(curr.effect == effect)
				{
					curr.effect.update(stage3D, camera);
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
			var curr:EffectList = effects[camera];
			
			while(curr != null)
			{
				curr.effect.update(stage3D, camera);
				curr = curr.next;
			}
		}
		
		/*---------------------------
		Helpers
		---------------------------*/
		
		// ..
	}
}

import alternativa.engine3d.post.effects.PostEffect;

internal class EffectList
{
	public var effect:PostEffect;
	public var next:EffectList;
}