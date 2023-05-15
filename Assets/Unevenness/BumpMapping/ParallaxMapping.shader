Shader "Unlit/ParallaxlMapping"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        [Normal] _NormalMap("NormalMap", 2D) = "bump"
        _HeightMap("HeightMap", 2D) = "white"{}
        _Shininess("Shininess", Float) = 0.07
        _HeightFactor("HeightFactor", Float) = 0.5
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
                float4 vertex : SV_POSITION;
                float3 viewDirTS : TEXCOORD1;
                float3 lightDir : TEXCOORD2;
                float3 lightColor : COLOR;
            };

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);

            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            TEXTURE2D(_HeightMap);
            SAMPLER(sampler_HeightMap);

            float _Shininess;
            float _HeightFactor;

            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float4 _NormalMap_ST;
            float4 _HeightMap_ST;
            CBUFFER_END

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                /*
                 * 
                 */
                float3 binormal = cross(normalize(v.normal), normalize(v.tangent.xyz)) * v.tangent.w;
                float3x3 rotation = float3x3(v.tangent.xyz, binormal, v.normal);

                Light light = GetMainLight();
                /*
                 * ピクセルシェーダーに受け渡される光源ベクトルや視線ベクトルを
                 * 法線マップを適用するポリゴン基準の座標系とテクスチャの座標系が合うように変換する
                 * ピクセルシェーダーで座標変換すると全ピクセルにおいて、取り出した法線ベクトルに対して座標変換するので負荷が重い
                 */
                o.lightDir = mul(rotation, light.direction);
                o.viewDirTS = mul(rotation, GetObjectSpaceNormalizeViewDir(v.vertex));
                o.lightColor = light.color;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                i.lightDir = normalize(i.lightDir);
                i.viewDirTS = normalize(i.viewDirTS);
                float3 halfVec = normalize(i.lightDir + i.viewDirTS);

                /*
                 * ハイトマップをサンプリングしてuvをずらす
                 */
                float4 height = SAMPLE_TEXTURE2D(_HeightMap, sampler_HeightMap, i.uv);
                i.uv += i.viewDirTS.xy * height.r * _HeightFactor;
                
                float4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                float3 normal = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv));

                normal = normalize(normal);

                float4 color;
                float3 diffuse = max(0, dot(normal, i.lightDir)) * i.lightColor;
                float3 specular = pow(max(0, dot(normal, halfVec)), _Shininess * 128) * i.lightColor;
                
                color.rgb = tex * diffuse + specular;
                
                return color;
            }
            ENDHLSL
        }
    }
}