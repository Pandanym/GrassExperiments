Shader "Unlit/GrassShader"
{
    Properties
    {
        _BottomColor("BottomColor", Color) = (1,1,1,1)
        _TopColor("TopColor", Color) = (1,1,1,1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100
        Cull Off
        Lighting Off
        ZWrite On
        ZTest LEqual

        Pass
        {
            CGPROGRAM
            #pragma target 5.0
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            #define ID_PER_PRIMITIVE 6

            // Simple noise function, sourced from http://answers.unity.com/answers/624136/view.html
            // Extended discussion on this function can be found at the following link:
            // https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
            // Returns a number in the 0...1 range.
            float rand(float3 co)
            {
                return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
            }

            // Construct a rotation matrix that rotates around the provided axis, sourced from:
            // https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
            float3x3 AngleAxis3x3(float angle, float3 axis)
            {
                float c, s;
                sincos(angle, s, c);

                float t = 1 - c;
                float x = axis.x;
                float y = axis.y;
                float z = axis.z;

                return float3x3(
                    t * x * x + c, t * x * y - s * z, t * x * z + s * y,
                    t * x * y + s * z, t * y * y + c, t * y * z - s * x,
                    t * x * z - s * y, t * y * z + s * x, t * z * z + c
                    );
            }

            float2 GetCorner(uint index)
            {
            #if 0
                const float2 corners[ID_PER_PRIMITIVE] = { float2(-0.5, -0.5), float2(-0.5, 0.5), float2(0.5, 0.5), float2(0.5, 0.5), float2(0.5, -0.5), float2(-0.5, -0.5) };
                return corners[index % ID_PER_PRIMITIVE];
            #else
                return float2((index >= 2 && index <= 4) ? 0.05 : -0.05, (index >= 1 && index <= 3) ? 1 : 0);
            #endif
            }

            struct GrassBlade
            {
                float3 position;
                float height;
                float defaultHeight;
                float bend;
                float3 direction;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : POSITION;
                fixed4 color : COL;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _BottomColor;
            fixed4 _TopColor;
            float4 _PointerPos;
            float4 _PointerDirection;
            int _PointerActive;
            
            uniform RWStructuredBuffer<GrassBlade> GrassBladeBuffer : register(u1);

            v2f vert (uint id : SV_VertexID)
            {
                uint objectIndex = id / ID_PER_PRIMITIVE;
                uint vertexIndex = id % ID_PER_PRIMITIVE;

                v2f o;

                // quad shape
                float3 vertex = float3(GetCorner(vertexIndex), 0);
                // taper the end of the grass blade
                vertex.x *= (1-vertex.y) + .2;
                vertex.y *= GrassBladeBuffer[objectIndex].height;

                // get blade position in buffer
                float3 grassBladePosition = GrassBladeBuffer[objectIndex].position;

                // random rotate based on blade position
                vertex = mul(AngleAxis3x3(rand(grassBladePosition) * UNITY_TWO_PI, float3(0, 1, 0)), vertex);

                if (distance(grassBladePosition, _PointerPos) <= 1.2 && _PointerActive > 0)
                {
                    GrassBladeBuffer[objectIndex].bend += smoothstep(1.2, 0, distance(grassBladePosition, _PointerPos)) * unity_DeltaTime * 20 * smoothstep(0,.2, length(_PointerDirection));
                    GrassBladeBuffer[objectIndex].bend = clamp(GrassBladeBuffer[objectIndex].bend, 0, 1);

                    GrassBladeBuffer[objectIndex].direction = lerp(GrassBladeBuffer[objectIndex].direction, normalize(_PointerDirection), 50 * unity_DeltaTime * (1 - GrassBladeBuffer[objectIndex].bend) * smoothstep(0, .2, length(_PointerDirection)) );
                }                    
                GrassBladeBuffer[objectIndex].bend -= smoothstep(1, 1.2, distance(grassBladePosition, _PointerPos)) * unity_DeltaTime * .3;
                GrassBladeBuffer[objectIndex].bend = clamp(GrassBladeBuffer[objectIndex].bend, 0, 1);

                vertex = mul(AngleAxis3x3(GrassBladeBuffer[objectIndex].bend * UNITY_TWO_PI *.25, cross(float3(0, 1, 0), GrassBladeBuffer[objectIndex].direction)), vertex);

                vertex += grassBladePosition;

                // vertex color
                o.color = lerp(_BottomColor, _TopColor, vertex.y);

                o.vertex = UnityObjectToClipPos(float4(vertex,1));

                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                // sample the texture
                fixed4 col = i.color;
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}
