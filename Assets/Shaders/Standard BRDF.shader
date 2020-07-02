// Upgrade NOTE: replaced 'defined FOG_COMBINED_WITH_WORLD_POS' with 'defined (FOG_COMBINED_WITH_WORLD_POS)'

Shader "Custom/StandardSurfaceShader"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200
    
        // ---- forward rendering base pass:
        Pass 
        {
            Name "FORWARD"
            Tags { "LightMode" = "ForwardBase" }
    
            CGPROGRAM
            // compile directives
            #pragma vertex vert_surf
            #pragma fragment frag_surf
            #pragma target 3.0
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma multi_compile_fwdbase
            #include "HLSLSupport.cginc"
            #define UNITY_INSTANCED_LOD_FADE
            #define UNITY_INSTANCED_SH
            #define UNITY_INSTANCED_LIGHTMAPSTS
            #include "UnityShaderVariables.cginc"
            #include "UnityShaderUtilities.cginc"
            // -------- variant for: <when no other keywords are defined>
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "UnityPBSLighting.cginc"
            #include "AutoLight.cginc"
    
            #define INTERNAL_DATA
            #define WorldReflectionVector(data,normal) data.worldRefl
            #define WorldNormalVector(data,normal) normal
            
    
    
            // vertex-to-fragment interpolation data
    
            struct v2f_surf 
            {
              UNITY_POSITION(pos);
              float2 pack0 : TEXCOORD0; // _MainTex
              float3 worldNormal : TEXCOORD1;
              float3 worldPos : TEXCOORD2;
              float4 lmap : TEXCOORD3;
              UNITY_FOG_COORDS(4)
              UNITY_SHADOW_COORDS(5)
              #ifdef DIRLIGHTMAP_COMBINED
              float3 tSpace0 : TEXCOORD6;
              float3 tSpace1 : TEXCOORD7;
              float3 tSpace2 : TEXCOORD8;
              #endif
              UNITY_VERTEX_INPUT_INSTANCE_ID
              UNITY_VERTEX_OUTPUT_STEREO
            };
            
            struct Input
            {
                float2 uv_MainTex;
            };
            
            sampler2D _MainTex;
            float4 _MainTex_ST;
            half _Glossiness;
            half _Metallic;
            fixed4 _Color;
            
            void surf (Input IN, inout SurfaceOutputStandard o)
            {
                // Albedo comes from a texture tinted by color
                fixed4 c = tex2D (_MainTex, IN.uv_MainTex) * _Color;
                o.Albedo = c.rgb;
                // Metallic and smoothness come from slider variables
                o.Metallic = _Metallic;
                o.Smoothness = _Glossiness;
                o.Alpha = c.a;
            }
    
            // vertex shader
            v2f_surf vert_surf (appdata_full v) 
            {
                UNITY_SETUP_INSTANCE_ID(v);
                v2f_surf o;
                UNITY_INITIALIZE_OUTPUT(v2f_surf,o);
                UNITY_TRANSFER_INSTANCE_ID(v,o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.pos = UnityObjectToClipPos(v.vertex);
                o.pack0.xy = TRANSFORM_TEX(v.texcoord, _MainTex);
                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                float3 worldNormal = UnityObjectToWorldNormal(v.normal);
                #if defined(LIGHTMAP_ON) && defined(DIRLIGHTMAP_COMBINED)
                    fixed3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
                    fixed tangentSign = v.tangent.w * unity_WorldTransformParams.w;
                    fixed3 worldBinormal = cross(worldNormal, worldTangent) * tangentSign;
                #endif
                #if defined(LIGHTMAP_ON) && defined(DIRLIGHTMAP_COMBINED) && !defined(UNITY_HALF_PRECISION_FRAGMENT_SHADER_REGISTERS)
                    o.tSpace0 = float4(worldTangent.x, worldBinormal.x, worldNormal.x, worldPos.x);
                    o.tSpace1 = float4(worldTangent.y, worldBinormal.y, worldNormal.y, worldPos.y);
                    o.tSpace2 = float4(worldTangent.z, worldBinormal.z, worldNormal.z, worldPos.z);
                #endif
                o.worldPos.xyz = worldPos;
                o.worldNormal = worldNormal;
                #ifdef DYNAMICLIGHTMAP_ON
                    o.lmap.zw = v.texcoord2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
                #endif
                #ifdef LIGHTMAP_ON
                    o.lmap.xy = v.texcoord1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
                #endif
                
                // SH/ambient and vertex lights
                #ifndef LIGHTMAP_ON
                    #if UNITY_SHOULD_SAMPLE_SH && !UNITY_SAMPLE_FULL_SH_PER_PIXEL
                      o.sh = 0;
                      // Approximated illumination from non-important point lights
                      #ifdef VERTEXLIGHT_ON
                        o.sh += Shade4PointLights (
                          unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
                          unity_LightColor[0].rgb, unity_LightColor[1].rgb, unity_LightColor[2].rgb, unity_LightColor[3].rgb,
                          unity_4LightAtten0, worldPos, worldNormal);
                      #endif
                      o.sh = ShadeSHPerVertex (worldNormal, o.sh);
                    #endif
                #endif // !LIGHTMAP_ON
                
                UNITY_TRANSFER_LIGHTING(o,v.texcoord1.xy); // pass shadow and, possibly, light cookie coordinates to pixel shader
                #ifdef FOG_COMBINED_WITH_TSPACE
                    UNITY_TRANSFER_FOG_COMBINED_WITH_TSPACE(o,o.pos); // pass fog coordinates to pixel shader
                #elif defined (FOG_COMBINED_WITH_WORLD_POS)
                    UNITY_TRANSFER_FOG_COMBINED_WITH_WORLD_POS(o,o.pos); // pass fog coordinates to pixel shader
                #else
                    UNITY_TRANSFER_FOG(o,o.pos); // pass fog coordinates to pixel shader
                #endif
                return o;
            }
    
            // fragment shader
            fixed4 frag_surf (v2f_surf IN) : SV_Target 
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                // prepare and unpack data
                Input surfIN;
                #ifdef FOG_COMBINED_WITH_TSPACE
                    UNITY_EXTRACT_FOG_FROM_TSPACE(IN);
                #elif defined (FOG_COMBINED_WITH_WORLD_POS)
                    UNITY_EXTRACT_FOG_FROM_WORLD_POS(IN);
                #else
                    UNITY_EXTRACT_FOG(IN);
                #endif
                UNITY_INITIALIZE_OUTPUT(Input,surfIN);
                surfIN.uv_MainTex.x = 1.0;
                surfIN.uv_MainTex = IN.pack0.xy;
                float3 worldPos = IN.worldPos.xyz;
                #ifndef USING_DIRECTIONAL_LIGHT
                    fixed3 lightDir = normalize(UnityWorldSpaceLightDir(worldPos));
                #else
                    fixed3 lightDir = _WorldSpaceLightPos0.xyz;
                #endif
                
                float3 worldViewDir = normalize(UnityWorldSpaceViewDir(worldPos));
                
                #ifdef UNITY_COMPILER_HLSL
                    SurfaceOutputStandard o = (SurfaceOutputStandard)0;
                #else
                    SurfaceOutputStandard o;
                #endif
                
                o.Albedo = 0.0;
                o.Emission = 0.0;
                o.Alpha = 0.0;
                o.Occlusion = 1.0;
                fixed3 normalWorldVertex = fixed3(0,0,1);
                o.Normal = IN.worldNormal;
                normalWorldVertex = IN.worldNormal;
                
                // call surface function
                surf (surfIN, o);
                
                // compute lighting & shadowing factor
                UNITY_LIGHT_ATTENUATION(atten, IN, worldPos)
                fixed4 c = 0;
                
                // Setup lighting environment
                UnityGI gi;
                    UNITY_INITIALIZE_OUTPUT(UnityGI, gi);
                    gi.indirect.diffuse = 0;
                    gi.indirect.specular = 0;
                    gi.light.color = _LightColor0.rgb;
                    gi.light.dir = lightDir;
    
                // Call GI (lightmaps/SH/reflections) lighting function
                UnityGIInput giInput;
                UNITY_INITIALIZE_OUTPUT(UnityGIInput, giInput);
                giInput.light = gi.light;
                giInput.worldPos = worldPos;
                giInput.worldViewDir = worldViewDir;
                giInput.atten = atten;
                #if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
                    giInput.lightmapUV = IN.lmap;
                #else
                    giInput.lightmapUV = 0.0;
                #endif
                #if UNITY_SHOULD_SAMPLE_SH && !UNITY_SAMPLE_FULL_SH_PER_PIXEL
                    giInput.ambient = IN.sh;
                #else
                    giInput.ambient.rgb = 0.0;
                #endif
                giInput.probeHDR[0] = unity_SpecCube0_HDR;
                giInput.probeHDR[1] = unity_SpecCube1_HDR;
                #if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECCUBE_BOX_PROJECTION)
                    giInput.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
                #endif
                #ifdef UNITY_SPECCUBE_BOX_PROJECTION
                    giInput.boxMax[0] = unity_SpecCube0_BoxMax;
                    giInput.probePosition[0] = unity_SpecCube0_ProbePosition;
                    giInput.boxMax[1] = unity_SpecCube1_BoxMax;
                    giInput.boxMin[1] = unity_SpecCube1_BoxMin;
                    giInput.probePosition[1] = unity_SpecCube1_ProbePosition;
                #endif
                
                LightingStandard_GI(o, giInput, gi);
                
                // realtime lighting: call lighting function
                c += LightingStandard (o, worldViewDir, gi);
                UNITY_APPLY_FOG(_unity_fogCoord, c); // apply fog
                UNITY_OPAQUE_ALPHA(c.a);
                return c;
            }
            ENDCG
        }
    }
}