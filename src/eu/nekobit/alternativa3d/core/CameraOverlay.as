package eu.nekobit.alternativa3d.core
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.core.Camera3D;
	import alternativa.engine3d.core.DrawUnit;
	import alternativa.engine3d.core.Light3D;
	import alternativa.engine3d.core.Object3D;
	import alternativa.engine3d.core.VertexAttributes;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	import alternativa.engine3d.resources.Geometry;
	
	import eu.nekobit.alternativa3d.core.renderers.NekoRenderer;
	import eu.nekobit.alternativa3d.post.effects.PostEffect;
	
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.VertexBuffer3D;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;
	
	/**
	 * @private
	 * 
	 * @author Varnius
	 */
	public class CameraOverlay extends Object3D
	{	
		private static var caches:Dictionary = new Dictionary(true);
		private var cachedContext3D:Context3D;		
		private var cachedPrograms:Dictionary;
		
		public var effect:PostEffect;
		
		alternativa3d var geometry:Geometry = new Geometry(4);
		alternativa3d var diffuseMap:Texture;
		alternativa3d var maskMap:Texture;
		alternativa3d var blendAmount:Number = 1.0;
		alternativa3d var blendFactorSource:String = Context3DBlendFactor.SOURCE_ALPHA;
		alternativa3d var blendFactorDestination:String = Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;
		
		// Geometry stream attributes
		private var attributes:Array =
		[
			VertexAttributes.POSITION,
			VertexAttributes.POSITION,
			VertexAttributes.POSITION,
			VertexAttributes.TEXCOORDS[0],
			VertexAttributes.TEXCOORDS[0],
		];
		
		public function CameraOverlay()
		{			
			// Vertex/UV buffer for simple overlay geometry
			var vertices:Vector.<Number> = new <Number>[
				-1,  1, 0,
				-1, -1, 0,
				1,  1, 0,
				1, -1, 0
			];
			
			// Vertex/UV buffer for simple overlay geometry
			var uvs:Vector.<Number> = new <Number>[
				0, 0,
				0, 1,
				1, 0,
				1, 1
			];
			
			// Index buffer for that same overlay geometry
			var indices:Vector.<uint> = new <uint>[
				0,1,2,
				2,1,3
			];
			
			geometry.addVertexStream(attributes);		
			geometry.numVertices = 4;				
			geometry.setAttributeValues(VertexAttributes.POSITION, vertices);
			geometry.setAttributeValues(VertexAttributes.TEXCOORDS[0], uvs);
			geometry.indices = indices;	
			
			mouseEnabled = false;
			mouseChildren = false;
		}		
		
		/**
		 * @private 
		 */
		alternativa3d override function collectDraws(camera:Camera3D, lights:Vector.<Light3D>, lightsLength:int, useShadow:Boolean):void
		{
			if(diffuseMap == null)
			{
				return;
			}
			
			if(!(camera.renderer is NekoRenderer))
			{
				return;
			}
			
			var renderer:NekoRenderer = camera.renderer as NekoRenderer;
			
			// Refresh cache if context3D cahnges
			if(camera.context3D != cachedContext3D)
			{
				cachedContext3D = camera.context3D;
				cachedPrograms = caches[cachedContext3D];
				
				if(cachedPrograms == null)
				{
					cachedPrograms = new Dictionary();
					caches[cachedContext3D] = cachedPrograms;
				}
			}	
			
			// Get program
			var shaderProgram:OverlayShaderProgram = getProgram(caches[cachedContext3D] as Dictionary);
			
			// Get buffers
			var positionBuffer:VertexBuffer3D = geometry.getVertexBuffer(VertexAttributes.POSITION);
			var uvBuffer:VertexBuffer3D = geometry.getVertexBuffer(VertexAttributes.TEXCOORDS[0]);
			
			if(positionBuffer == null || uvBuffer == null)
			{
				return;
			}
			
			var drawUnit:DrawUnit = renderer.createDrawUnit(this, shaderProgram.program, geometry._indexBuffer, 0, 2);
			
			// Set vertex/UV attribute streams
			drawUnit.setVertexBufferAt(shaderProgram.aPosition, positionBuffer, 0, VertexAttributes.FORMATS[VertexAttributes.POSITION]);
			drawUnit.setVertexBufferAt(shaderProgram.aUV, uvBuffer, geometry._attributesOffsets[VertexAttributes.TEXCOORDS[0]], VertexAttributes.FORMATS[VertexAttributes.TEXCOORDS[0]]);
			
			// Set fragment constants
			// w used for storing constant 1
			drawUnit.setFragmentConstantsFromNumbers(shaderProgram.cAmount, blendAmount, 0, 0, 1);		
			
			// Set samplers
			drawUnit.setTextureAt(shaderProgram.sDiffuseMap, diffuseMap);
			
			if(maskMap != null)
			{
				drawUnit.setTextureAt(shaderProgram.sMaskMap, maskMap);
			}
			
			drawUnit.blendSource = blendFactorSource;
			drawUnit.blendDestination = blendFactorDestination;
			renderer.addDrawUnit(drawUnit, NekoRenderer.NEKO_POST_OVERLAY);			
		}
		
		private function getProgram(programs:Dictionary):OverlayShaderProgram
		{
			var key:String = maskMap == null ? "diffuseProgram" : "maskProgram";
			var program:OverlayShaderProgram = cachedPrograms[key];
			
			if(program == null)
			{
				var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
				var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);
				
				// Vertex
				vertexLinker.addProcedure(vertexProcedure);
				
				// Fragment
				if(maskMap != null)
				{
					fragmentLinker.addProcedure(maskFragmentProcedure);
				}
				else 
				{
					fragmentLinker.addProcedure(fragmentProcedure);
				}			
				
				fragmentLinker.varyings = vertexLinker.varyings;
				
				program = new OverlayShaderProgram(vertexLinker, fragmentLinker);
				program.upload(cachedContext3D);
				programs[key] = program;
			}		
			
			return program;
		}
		
		/**
		 * @private
		 */
		alternativa3d override function fillResources(resources:Dictionary, hierarchy:Boolean = false, resourceType:Class = null):void {
			if (geometry != null && (resourceType == null || geometry is resourceType)) resources[geometry] = true;
			super.fillResources(resources, hierarchy, resourceType);
		}
		
		/*---------------------------
		Shader procedures
		---------------------------*/
		
		static alternativa3d const vertexProcedure:Procedure = new Procedure(
		[			
			// Declarations
			"#a0=aPosition",			
			"#a1=aUV",
			"#v0=vUV",
			
			"mov v0 a1",
			"mov o0 a0",
		], "vertexProcedure");
		
		static alternativa3d const fragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sDiffuseMap",			
			"#v0=vUV",
			"#c0=cAmount",
			
			"tex t0,v0,s0 <2d,clamp,linear>",
			"mul t0 t0 c0.x",
			"mov o0, t0"
		], "fragmentProcedure");
		
		static alternativa3d const maskFragmentProcedure:Procedure = new Procedure(
		[
			// Declarations
			"#s0=sDiffuseMap",
			"#s1=sMaskMap",
			"#v0=vUV",
			"#c0=cAmount",
			
			// Sample diffuse
			"tex t0,v0,s0 <2d,clamp,linear>",
			// Sample mask
			"tex t1,v0,s1 <2d,clamp,linear>",
			// 1 - mask alpha value
			"sub t1.w c0.w t1.w",
			// Apply mask
			"mul t0 t0 t1.w",
			// Multiply by blend amount
			"mul t0 t0 c0.x",
			// Output
			"mov o0, t0"
		], "maskFragmentProcedure");
	}
}
import alternativa.engine3d.materials.ShaderProgram;
import alternativa.engine3d.materials.compiler.Linker;

import flash.display3D.Context3D;

/**
 * Used for filtering rendered glow map.
 */
class OverlayShaderProgram extends ShaderProgram
{
	// Vertex
	public var aPosition:int = -1;
	public var aUV:int = -1;
	
	// Fragment
	public var sDiffuseMap:int = -1;	
	public var cAmount:int = -1;
	
	// Fragment - mask
	public var sMaskMap:int = -1;
	
	public function OverlayShaderProgram(vertex:Linker, fragment:Linker)
	{
		super(vertex, fragment);
	}
	
	override public function upload(context3D:Context3D):void
	{
		super.upload(context3D);
		
		// Vertex shader
		aPosition = vertexShader.findVariable("aPosition");
		aUV = vertexShader.findVariable("aUV");
		
		// Fragment shader
		sDiffuseMap = fragmentShader.findVariable("sDiffuseMap");
		cAmount = fragmentShader.findVariable("cAmount");
		
		// Fragment - mask
		sMaskMap = fragmentShader.findVariable("sMaskMap");
	}
}