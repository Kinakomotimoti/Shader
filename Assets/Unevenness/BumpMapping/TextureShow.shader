Shader "Unlit/TextureShow"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        
        _Shininess("Shininess", Float) = 0.07
    }
    SubShader
    {
        Tags { "Queue"="Geometry" "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline"}
        LOD 100

        Pass
        {
            Name "TextureShow"
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

            float _Shininess;

            CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float4 _NormalMap_ST;
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
                
                float4 tex = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                return tex;
            }
            ENDHLSL
        }
    }
}