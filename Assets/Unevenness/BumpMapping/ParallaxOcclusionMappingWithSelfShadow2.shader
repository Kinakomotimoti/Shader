Shader "Unlit/ParallaxlOcclusionMappingWithSelfShadow2"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        [Normal] _NormalMap("NormalMap", 2D) = "bump"
        _HeightMap("HeightMap", 2D) = "white"{}
        _Shininess("Shininess", Float) = 0.07
        _HeightFactor("HeightFactor", Float) = 0.5
        
        _RayStep("RayStep", Int) = 16
        _MaxHeight("MaxHeight", Float) = 1.0
        
        _HardShadowColor("HardShadowColor", Color) = (0,0,0,1)
        _ShadowStepFactor("ShadowStepFactor", Float) = 0.5
        
        _ShadowIntensity("ShadowIntensity", Float) = 5
    }
    SubShader
    {
        Tags { "Queue"="Geometry" "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline"}
        LOD 100

        Pass
        {
            Name "Normal"
            Tags { "LightMode"="UniversalForward"}
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 position : SV_POSITION;
                float3 viewDirTS : TEXCOORD1;
                float3 lightDir : TEXCOORD2;
                float3 lightColor : TEXCOORD3;
                float2 parallaxOffset : TEXCOORD4;
                float4 positionWS : TEXCOORD5;
                float3 lightPosition : TEXCOORD6;
                float3 worldPos : TEXCOORD7;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            TEXTURE2D(_HeightMap);
            SAMPLER(sampler_HeightMap);

            float _Shininess;
            float _HeightFactor;

            int _RayStep;
            float _MaxHeight;

            float4 _HardShadowColor;

            float _ShadowStepFactor;
            float _ShadowIntensity;

            float4 _VirtualLightPosition;

            #define RAY_SAMPLE_COUNT 32;

            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float4 _NormalMap_ST;
            float4 _HeightMap_ST;
            CBUFFER_END

            v2f vert (appdata v)
            {
                v2f o;
                o.position = TransformObjectToHClip(v.vertex.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                /*
                 * 
                 */
                //VertexNormalInputs normalInputs = GetVertexNormalInputs(v.vertex);
                float3 binormal = cross(normalize(v.normal), normalize(v.tangent.xyz)) * v.tangent.w;
                float3x3 rotation = float3x3(v.tangent.xyz, binormal, v.normal);

                Light light = GetMainLight(0);
                /*
                 * ピクセルシェーダーに受け渡される光源ベクトルや視線ベクトルを
                 * 法線マップを適用するポリゴン基準の座標系とテクスチャの座標系が合うように変換する
                 * ピクセルシェーダーで座標変換すると全ピクセルにおいて、取り出した法線ベクトルに対して座標変換するので負荷が重い
                 */
                o.lightDir = mul(rotation, light.direction);
                o.viewDirTS = mul(rotation, GetObjectSpaceNormalizeViewDir(v.vertex));
                o.lightColor = light.color;
                //o.lightPosition = float3(_MainLightPosition.xyz);
                
                float3 virtualLightPositionDir = _VirtualLightPosition.xyz - mul(unity_ObjectToWorld, v.vertex).xyz;
                o.lightPosition = mul(rotation, virtualLightPositionDir);

                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                //return float4(i.lightDir, 0);
                i.lightPosition = normalize(i.lightPosition);
                i.lightDir = normalize(i.lightDir);
                i.viewDirTS = normalize(i.viewDirTS);
                float3 halfVec = normalize(i.lightDir + i.viewDirTS);

                /*
                 * ハイトマップをサンプリングしてuvをずらす
                 */
                float heightMax = 1;
                float heightMin = 0;
                const int stepCount = 32;
                float rayStepLength = (heightMax - heightMin) / stepCount;
                float rayHeight = heightMax;
                float height = SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, i.uv);
                
                float2 uv = i.uv;
                float2 uvStart = i.uv;
                float2 uvOffset = uv;
                
                for (int loopCount = 0; loopCount < stepCount; loopCount++)
                {
                    uvOffset = i.viewDirTS * loopCount * rayStepLength * _HeightFactor;
                    uv = uvStart + uvOffset;
                    height = SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, uv).r;

                    if(rayHeight < height)
                    {
                        break;
                    }
                    
                    rayHeight -= rayStepLength;
                }
                
                float weight = 0.5;
                float2 beforeUV = uv - uvOffset;
                uv = lerp(uv, beforeUV, weight);
                
                float4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
                float3 normal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, uv));

                normal = normalize(normal);
                
                float4 color = 0;
                float3 diffuse = max(0, dot(normal, i.lightDir)) * i.lightColor;
                float3 specular = pow(max(0, dot(normal, halfVec)), _Shininess * 128) * i.lightColor;
                
                color.rgb = tex * diffuse + specular;

                const int selfShadowStepCount = 16;
                // rayが衝突した位置からオブジェクトを抜けるまでステップを進める
                float selfShadowLength = (heightMax - rayHeight) / selfShadowStepCount;
                float selfShadowHeight = rayHeight + rayStepLength;

                float2 selfShadowUv = uv;
                float2 selfShadowUvStart = uv;
                float2 selfShadowUvOffset = beforeUV;

                float selfShadow = 1;
                
                for (int shadowLoopCount = 1; shadowLoopCount < selfShadowStepCount; shadowLoopCount++)
                {
                    selfShadowUvOffset = i.lightDir * shadowLoopCount * selfShadowLength * _ShadowStepFactor;
                    selfShadowUv = selfShadowUvStart + selfShadowUvOffset;
                    height = SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, selfShadowUv).r;

                    if(selfShadowHeight < height)
                    {
                        selfShadow -= (height - selfShadowHeight) * _ShadowIntensity;
                        selfShadow = max(0, selfShadow);
                        break;
                    }
                    
                    selfShadowHeight += selfShadowLength;
                }
                
                return color * selfShadow;
            }
            ENDHLSL
        }
    }
}