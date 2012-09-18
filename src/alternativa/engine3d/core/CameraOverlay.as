package alternativa.engine3d.core
{
	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.materials.ShaderProgram;
	import alternativa.engine3d.materials.compiler.Linker;
	import alternativa.engine3d.materials.compiler.Procedure;
	import alternativa.engine3d.resources.Geometry;
	
	import flash.display3D.Context3D;
	import flash.display3D.Context3DBlendFactor;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.VertexBuffer3D;
	import flash.display3D.textures.Texture;
	import flash.utils.Dictionary;
	
	use namespace alternativa3d;
	
	public class CameraOverlay extends Object3D
	{	
		private static const cachedPrograms:Dictionary = new Dictionary(true);		
		private var cachedContext3D:Context3D;
		
		alternativa3d var geometry:Geometry = new Geometry(4);
		alternativa3d var diffuseMap:Texture;
		alternativa3d var blendAmount:Number = 1.0;
		alternativa3d var blendFactorSource:String = Context3DBlendFactor.SOURCE_ALPHA;
		alternativa3d var blendFactorDestination:String = Context3DBlendFactor.ONE_MINUS_SOURCE_ALPHA;
		
		/**
		 * @private
		 */
		alternativa3d var shaderProgram:OverlayShaderProgram;
		
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
			
			// Update cached context3D and program when context3D changes
			if(camera.context3D != cachedContext3D)
			{
				cachedContext3D = camera.context3D;
				shaderProgram = cachedPrograms[cachedContext3D];
				
				if(shaderProgram == null)
				{
					shaderProgram = getProgram();
					shaderProgram.upload(cachedContext3D);
					cachedPrograms[cachedContext3D] = shaderProgram;
				}
			}			
			
			// Get buffers
			var positionBuffer:VertexBuffer3D = geometry.getVertexBuffer(VertexAttributes.POSITION);
			var uvBuffer:VertexBuffer3D = geometry.getVertexBuffer(VertexAttributes.TEXCOORDS[0]);
			
			var drawUnit:DrawUnit = camera.renderer.createDrawUnit(this, shaderProgram.program, geometry._indexBuffer, 0, 2);
			
			// Set vertex/UV attribute streams
			drawUnit.setVertexBufferAt(shaderProgram.aPosition, positionBuffer, 0, VertexAttributes.FORMATS[VertexAttributes.POSITION]);
			drawUnit.setVertexBufferAt(shaderProgram.aUV, uvBuffer, geometry._attributesOffsets[VertexAttributes.TEXCOORDS[0]], VertexAttributes.FORMATS[VertexAttributes.TEXCOORDS[0]]);
			
			// Set fragment constants
			drawUnit.setFragmentConstantsFromNumbers(shaderProgram.cAmount, blendAmount, 0,0,0);
			
			// Set samplers
			drawUnit.setTextureAt(shaderProgram.sDiffuseMap, diffuseMap);
			
			drawUnit.blendSource = blendFactorSource;
			drawUnit.blendDestination = blendFactorDestination;			
			camera.renderer.addDrawUnit(drawUnit, /*objectRenderPriority >= 0 ? objectRenderPriority :*/ Renderer.TRANSPARENT_SORT);
		}
		
		private function getProgram():OverlayShaderProgram
		{
			var vertexLinker:Linker = new Linker(Context3DProgramType.VERTEX);
			var fragmentLinker:Linker = new Linker(Context3DProgramType.FRAGMENT);
			
			// Vertex
			vertexLinker.addProcedure(vertexProcedure);
			
			// Fragment
			fragmentLinker.addProcedure(fragmentProcedure);
			fragmentLinker.varyings = vertexLinker.varyings;
			
			return new OverlayShaderProgram(vertexLinker, fragmentLinker);			
		}
		
		/**
		 * @private
		 */
		alternativa3d override function fillResources(resources:Dictionary, hierarchy:Boolean = false, resourceType:Class = null):void {
			if (geometry != null && (resourceType == null || geometry is resourceType)) resources[geometry] = true;
			super.fillResources(resources, hierarchy, resourceType);
		}
		
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
			
			"tex t0,v0,s0 <2d,repeat,linear>",
			"mul t0 t0 c0.x",
			"mov o0, t0"
		], "fragmentProcedure");
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
	}
}