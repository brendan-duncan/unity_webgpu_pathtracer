Shader "Hidden/PathTracer/Presentation"
{

    CGINCLUDE
        #pragma target 4.5
        #include "util/tonemap.hlsl"
  
        struct Attributes
        {
            float4 vertex : POSITION;
            float4 texcoord : TEXCOORD0;
        };

        struct Varyings
        {
            float2 uv : TEXCOORD0;
            float4 vertex : SV_POSITION;
        };

        sampler2D _MainTex;
        float Exposure;
        int Mode;

        Varyings VertBlit(Attributes v)
        {
            Varyings o;
            o.vertex = UnityObjectToClipPos(v.vertex);
            o.uv = v.texcoord;
            return o;
        }

        half4 FragBlit(Varyings i) : SV_Target
        {
            float3 color = tex2D(_MainTex, i.uv).rgb;
            if (Exposure > 0.0f)
            {
                color *= 1.0f / exp2(Exposure);
            }
            switch (Mode)
            {
                case 0:
                    color = Aces(color);
                    break;
                case 1:
                    color = Filmic(color);
                    break;
                case 2:
                    color = Reinhard(color);
                    break;
                default:
                    color = Lottes(color);
                    break;
            }
            float3 srgb = pow(color, 1.0f / 2.2f);
            return half4(srgb, 1.0f);
        }
    ENDCG

    SubShader
    {
        Cull Off ZWrite Off ZTest Always

        Pass
        {
            CGPROGRAM
                #pragma vertex VertBlit
                #pragma fragment FragBlit
            ENDCG
        }
    }
}