Shader "Hidden/PathTracer/Presentation"
{
    CGINCLUDE
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
        bool sRGB;

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
            color *= Exposure;
            /*if (Exposure > 0.0f)
            {
                color *= 1.0f / exp2(Exposure); // Exposure Stops
            }*/

            switch (Mode)
            {
                case 1:
                    color = Aces(color);
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
            {
                float3 srgb = pow(color, 1.0f / 2.2f);
                return half4(srgb, 1.0f);
            }
            return half4(color, 1.0f);
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