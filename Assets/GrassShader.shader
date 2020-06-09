Shader "Unlit/GrassShader"
{
    Properties
    {
        _BottomColor("BottomColor", Color) = (1,1,1,1)
        _TopColor("TopColor", Color) = (1,1,1,1)
        _WindDistortionMap("Wind Distortion Map", 2D) = "white" {}
        _WindFrequency("Wind Frequency", Vector) = (0.05, 0.05, 0, 0)
        _WindStrength("Wind Strength", Float) = 1
    }
    SubShader
    {
        Tags { "LightMode" = "ForwardBase" }
        LOD 100
        Cull Off
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

            // necessary for UNITY_TRANSFER_SHADOW and UNITY_SHADOW_COORDS
            #define SHADOWS_SCREEN
            #include "UnityCG.cginc"
            #include "AutoLight.cginc" 

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

            // Get the vertex position to form a quad based on the vertex index (0->5)
            float2 GetCorner(uint index)
            {
            #if 0
                const float2 corners[ID_PER_PRIMITIVE] = { float2(-0.5, -0.5), float2(-0.5, 0.5), float2(0.5, 0.5), float2(0.5, 0.5), float2(0.5, -0.5), float2(-0.5, -0.5) };
                return corners[index % ID_PER_PRIMITIVE];
            #else
                return float2((index >= 2 && index <= 4) ? 1 : -1, (index >= 1 && index <= 3) ? 1 : 0);
            #endif
            }


            struct GrassBlade
            {
                float3 position;
                float height;
                float defaultHeight;
                float bend;
                float bendVelocity;
                float3 direction;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0; 
                UNITY_SHADOW_COORDS(2)
                UNITY_FOG_COORDS(1)
                float4 pos : POSITION;
                fixed4 color : COL;
            }; 

            sampler2D _WindDistortionMap;
            float4 _WindDistortionMap_ST;
            float2 _WindFrequency; 
            float _WindStrength;

            sampler2D _ShadowTexture;
            sampler2D _MainTex;
            float4 _MainTex_ST;
            fixed4 _BottomColor;
            fixed4 _TopColor;
            float3 _PointerPos;
            float3 _PointerDirection;
            int _PointerActive;
            float _GrassSpringForce;
            float _GrassSpringDamping;
            float _GrassBendForce;
            int _Simulate;
            int _ShadowCaster;

            
            uniform RWStructuredBuffer<GrassBlade> GrassBladeBuffer : register(u1);

            v2f vert (uint id : SV_VertexID)
            {
                uint objectIndex = id / ID_PER_PRIMITIVE;
                uint vertexIndex = id % ID_PER_PRIMITIVE;

                v2f o;

                // quad shape
                float3 vertex = float3(GetCorner(vertexIndex), 0);
                float3 localVertex = vertex;

                o.uv = vertex.xy;

                vertex.x *= .05;
                // taper the end of the grass blade
                vertex.x *= (1-vertex.y) + .2;
                vertex.y *= GrassBladeBuffer[objectIndex].height;

                // get blade position in buffer
                float3 grassBladePosition = GrassBladeBuffer[objectIndex].position;

                // random rotate based on blade position
                vertex = mul(AngleAxis3x3(rand(grassBladePosition) * UNITY_TWO_PI, float3(0, 1, 0)), vertex);

                float pointerDistanceMask = smoothstep(1.2, 0, distance(grassBladePosition, _PointerPos));
                float pointerVelocityMask = smoothstep(0, .5, length(_PointerDirection.xz));

                GrassBladeBuffer[objectIndex].bendVelocity += (-(_GrassSpringForce * GrassBladeBuffer[objectIndex].bend) - (_GrassSpringDamping * GrassBladeBuffer[objectIndex].bendVelocity)) * unity_DeltaTime * _Simulate;
                GrassBladeBuffer[objectIndex].bend += GrassBladeBuffer[objectIndex].bendVelocity * unity_DeltaTime * _Simulate;

                GrassBladeBuffer[objectIndex].bend += _GrassBendForce * pointerDistanceMask * pointerVelocityMask * _PointerActive * unity_DeltaTime * _Simulate;
                GrassBladeBuffer[objectIndex].bend = clamp(GrassBladeBuffer[objectIndex].bend, -1, 1);

                GrassBladeBuffer[objectIndex].direction = lerp(GrassBladeBuffer[objectIndex].direction, lerp(GrassBladeBuffer[objectIndex].direction,normalize(_PointerDirection), pointerDistanceMask * _PointerActive * (1-_Simulate)), 50 * (1 - _Simulate) * unity_DeltaTime * (1 - clamp(GrassBladeBuffer[objectIndex].bend, 0, 1)) * pointerVelocityMask);

                if (localVertex.y > 0) vertex = mul(AngleAxis3x3(GrassBladeBuffer[objectIndex].bend * UNITY_TWO_PI *.25, cross(float3(0, 1, 0), GrassBladeBuffer[objectIndex].direction)), vertex);

                // wind
                float2 windUV = grassBladePosition.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
                float2 windSample = (tex2Dlod(_WindDistortionMap, float4(windUV, 0, 0)).xy * 2 - 1) * _WindStrength;
                float3 windDirection = -normalize(float3(windSample.x, 0, windSample.y));

                float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, cross(float3(0,1,0),windDirection));

                if (localVertex.y > 0) vertex = mul(windRotation, vertex);

                vertex += grassBladePosition;

                // vertex color
                o.color = lerp(_BottomColor, _TopColor, vertex.y);

                o.pos = UnityObjectToClipPos(float4(vertex,1));

                o.pos = lerp(o.pos, UnityApplyLinearShadowBias(o.pos), _ShadowCaster);

                UNITY_TRANSFER_SHADOW(o, o.uv)

                UNITY_TRANSFER_FOG(o,o.pos);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            { 
                // sample shadowmap
                float3 shadowCoord = i._ShadowCoord.xyz / i._ShadowCoord.w;
                float shadowmap = tex2D(_ShadowTexture, shadowCoord.xy).b;

                // sample the texture
                fixed4 col = i.color * shadowmap;

                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);

                return col;
            }
            ENDCG
        }
    }
}
