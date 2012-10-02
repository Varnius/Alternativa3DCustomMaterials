package eu.nekobit.alternativa3d.resources
{
	import alternativa.engine3d.alternativa3d;
	
	import flash.display3D.Context3D;
	import flash.display3D.Context3DTextureFormat;
	import flash.display3D.textures.Texture;
	import alternativa.engine3d.resources.TextureResource;
	
	use namespace alternativa3d;
	
	/**
	 * A texture resource dedicated for direct rendering.
	 */
	public class RawTextureResource extends TextureResource
	{		
		/**
		 * Class constructor.
		 */
		public function RawTextureResource()
		{
			super();
		}
		
		/*---------------------------
		Public methods
		---------------------------*/
		
		/**
		 * Clears the texture.
		 * 
		 * @param context3D Context3D to use for rendering.
		 */
		public function reset(context3D:Context3D, width:Number, height:Number):void
		{
			if(_texture != null)
			{
				_texture.dispose();
			}
			
			_texture = context3D.createTexture(width, height, Context3DTextureFormat.BGRA, true);
		}
		
		/*---------------------------
		Getters/setters
		---------------------------*/
		
		/**
		 * Raw texture.
		 */
		public function get texture():Texture
		{
			return _texture as Texture;
		}
	}
}