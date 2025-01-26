Shader "Hidden/PathTracer/Presentation"
{
    CGINCLUDE
        #include "util/common.hlsl"
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
        float Brightness;
        float Contrast;
        float Saturation;
        float Vignette;
        int Mode;
        bool sRGB;

        Varyings VertBlit(Attributes v)
        {
            Varyings o;
            o.vertex = UnityObjectToClipPos(v.vertex);
            o.uv = v.texcoord;
            return o;
        }

        float4 FragBlit(Varyings i) : SV_Target
        {
            float3 color = tex2D(_MainTex, i.uv).rgb;

            color *= Exposure;

            switch (Mode)
            {
                case 1:
                    color = ACES(color);
                    break;
                case 2:
                    color = Filmic(color);
                    break;
                case 3:
                    color = Reinhard(color);
                    break;
                case 4:
                    color = Lottes(color);
                    break;
            }

            if (sRGB)
                color = LinearToSrgb(color);

            // Contrast and clamp
            color = saturate(lerp(0.5f, color, Contrast));

            color = pow(color, 1.0 / Brightness);

            float3 l = Luminance(color);
            color = lerp(l, color, Saturation);

            float2 centerUv = (i.uv - 0.5f) * 2.0f;
            color *= 1.0f - dot(centerUv, centerUv) * Vignette;

            return float4(color, 1.0f);
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
