﻿Shader "Nextidea/Character/Main Character"
{
    Properties
    {
        _MainTex("Albedo (RGB)", 2D) = "white" {}
        _Color("Color Tint", Color) = (1,1,1,1)
        _BumpMap("Normal (RGB)", 2D) = "bump" {}
        _BumpScale("Normal Scale", float) = 1
		
	[Header(Outline)]
        _Outline("Outline", Range(0,1)) = 0.001
        _OutlineColor("Outline Color", Color) = (0,0,0,1)

	[Header(Light Parameters)]
		_Lightmap("Light Texture (R: Ao G: Roughness B: Metallic A: Emission)", 2D) = "white"{}
        [Toggle]_GI("GI (On: Skybox Off: Gradient/Color)", float) = 1
		_GIIntensity("GI Intensity", Range(0,1)) = 1

	[Space(10)]
		_SpecularColor("Specular Color", Color) = (1,1,1,1)
		_SpecularScale("SpecularScale", Range(0,1)) = 0.1

	[Space(10)]
        _Smoothness("Smoothness", Range(0,1)) = 0.1
		_Metallic("Metallic", Range(0,1)) = 0

	[Space(10)]
		[Toggle(BLEEDING_AO)] _BLEEDING_AO("Color Bleeding AO", float) = 0
        _AOThresh ("Ambient Occlusion", Range(0, 3)) = 0
		// _AOColor ("AO Saturated", Color) = (0.4, 0.15, 0.13, 1)
	
	[Space(10)]
		[HDR]_EmissiveColor("Emissive Color", Color) = (1,1,1,1)
		_EmissiveIntensity("Emissive Intensity", Range(0,5)) = 0

	[Header(Rim Light)]
		[Toggle]_isFresnel("Is Fresnel", float) = 0
		_RimColor("Rim Color", Color) = (1,1,1,1)
		_RimAmount("Rim Amount", Range(0, 1)) = 0.716
		_RimThreshold("Rim Threshold", Range(0, 1)) = 0.1
		// _Fresnel("Fresnel", Range(1,10)) = 10

	[Header(Light Control)]
		_ShadowRange("Shadow Range", Range(-10,1)) = 0
		_ShadingSoftness("Shading Softness", Range(0,10)) = 1
		_brightColor("Bright Color", Color) = (1,1,1,1)
		_shadowColor("Shadow Color", Color) = (0,0,0,1)

	[Header(Color Grading)]
		_Brightness("Brightness", Range(0,2)) = 1
		_Saturation("Saturation", Range(0,2)) = 1
		_Contrast("Contrast", Range(0,2)) = 1
    }
    SubShader 
    {
		Tags { "RenderType"="Opaque" "Queue"="Geometry"}

		CGINCLUDE

			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#include "AutoLight.cginc"
			#include "UnityShaderVariables.cginc"

			#pragma shader_feature BLEEDING_AO

			half4 _Color;
			sampler2D _MainTex;
			float4 _MainTex_ST;
            sampler2D _BumpMap;
            float4 _BumpMap_ST;
            half _BumpScale;

			sampler2D _Lightmap;
			half _GI;
			float4 _Lightmap_ST;
			// float4 _AOColor;
			half _BLEEDING_AO;
			half _AOThresh;
			half4 _AOColor;
			half4 _SpecularColor;
			half _Smoothness;
			half _Metallic;
			// half _Fresnel;
			float4 _RimColor;
			float _RimAmount;
			float _RimThreshold;
			half4 _EmissiveColor;
			half _EmissiveIntensity;
			half _SpecularScale;

			half _ShadowRange;
			half _ShadingSoftness;
			half4 _shadowColor;
			half4 _brightColor;
			half _Brightness;
			half _Contrast;
			half _Saturation;
			half _isFresnel;
			half _GIIntensity;

			float _unity_fogCoord;

			struct lightStandard
            {
				half3 Albedo;      // base (diffuse or specular) color
				half3 Normal;      // tangent space normal, if written
                half Emission;
                half3 Specular;
                half Smoothness;   // 0=rough, 1=smooth
				half Metallic;     // 0=non-metal, 1=metal
			#ifdef BLEEDING_AO
                half3 Occlusion;    // dynamic anime Occlusion
			#else
				half Occlusion;    // occlusion (default 1)
			#endif
                half Alpha;        // alpha for transparencies
            };

			inline UnityGI UnityGI_Base_BleedAO(UnityGIInput data, half3 occlusion, half3 normalWorld)
			{
				UnityGI o_gi;
				ResetUnityGI(o_gi);

				// Base pass with Lightmap support is responsible for handling ShadowMask / blending here for performance reason
				#if defined(HANDLE_SHADOWS_BLENDING_IN_GI)
					half bakedAtten = UnitySampleBakedOcclusion(data.lightmapUV.xy, data.worldPos);
					float zDist = dot(_WorldSpaceCameraPos - data.worldPos, UNITY_MATRIX_V[2].xyz);
					float fadeDist = UnityComputeShadowFadeDistance(data.worldPos, zDist);
					data.atten = UnityMixRealtimeAndBakedShadows(data.atten, bakedAtten, UnityComputeShadowFade(fadeDist));
				#endif

				o_gi.light = data.light;
				o_gi.light.color *= data.atten;

				#if UNITY_SHOULD_SAMPLE_SH
					o_gi.indirect.diffuse = ShadeSHPerPixel(normalWorld, data.ambient, data.worldPos);
				#endif

				#if defined(LIGHTMAP_ON)
					// Baked lightmaps
					half4 bakedColorTex = UNITY_SAMPLE_TEX2D(unity_Lightmap, data.lightmapUV.xy);
					half3 bakedColor = DecodeLightmap(bakedColorTex);

					#ifdef DIRLIGHTMAP_COMBINED
						fixed4 bakedDirTex = UNITY_SAMPLE_TEX2D_SAMPLER (unity_LightmapInd, unity_Lightmap, data.lightmapUV.xy);
						o_gi.indirect.diffuse += DecodeDirectionalLightmap (bakedColor, bakedDirTex, normalWorld);

						#if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
							ResetUnityLight(o_gi.light);
							o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap (o_gi.indirect.diffuse, data.atten, bakedColorTex, normalWorld);
						#endif

					#else // not directional lightmap
						o_gi.indirect.diffuse += bakedColor;

						#if defined(LIGHTMAP_SHADOW_MIXING) && !defined(SHADOWS_SHADOWMASK) && defined(SHADOWS_SCREEN)
							ResetUnityLight(o_gi.light);
							o_gi.indirect.diffuse = SubtractMainLightWithRealtimeAttenuationFromLightmap(o_gi.indirect.diffuse, data.atten, bakedColorTex, normalWorld);
						#endif

					#endif
				#endif

				#ifdef DYNAMICLIGHTMAP_ON
					// Dynamic lightmaps
					fixed4 realtimeColorTex = UNITY_SAMPLE_TEX2D(unity_DynamicLightmap, data.lightmapUV.zw);
					half3 realtimeColor = DecodeRealtimeLightmap (realtimeColorTex);

					#ifdef DIRLIGHTMAP_COMBINED
						half4 realtimeDirTex = UNITY_SAMPLE_TEX2D_SAMPLER(unity_DynamicDirectionality, unity_DynamicLightmap, data.lightmapUV.zw);
						o_gi.indirect.diffuse += DecodeDirectionalLightmap (realtimeColor, realtimeDirTex, normalWorld);
					#else
						o_gi.indirect.diffuse += realtimeColor;
					#endif
				#endif

				o_gi.indirect.diffuse *= occlusion;
				return o_gi;
			}

			inline half3 UnityGI_IndirectSpecular_BleedAO(UnityGIInput data, half3 occlusion, Unity_GlossyEnvironmentData glossIn)
			{
				half3 specular;

				#ifdef UNITY_SPECCUBE_BOX_PROJECTION
					// we will tweak reflUVW in glossIn directly (as we pass it to Unity_GlossyEnvironment twice for probe0 and probe1), so keep original to pass into BoxProjectedCubemapDirection
					half3 originalReflUVW = glossIn.reflUVW;
					glossIn.reflUVW = BoxProjectedCubemapDirection (originalReflUVW, data.worldPos, data.probePosition[0], data.boxMin[0], data.boxMax[0]);
				#endif

				#ifdef _GLOSSYREFLECTIONS_OFF
					specular = unity_IndirectSpecColor.rgb;
				#else
					half3 env0 = Unity_GlossyEnvironment (UNITY_PASS_TEXCUBE(unity_SpecCube0), data.probeHDR[0], glossIn);
					#ifdef UNITY_SPECCUBE_BLENDING
						const float kBlendFactor = 0.99999;
						float blendLerp = data.boxMin[0].w;
						UNITY_BRANCH
						if (blendLerp < kBlendFactor)
						{
							#ifdef UNITY_SPECCUBE_BOX_PROJECTION
								glossIn.reflUVW = BoxProjectedCubemapDirection (originalReflUVW, data.worldPos, data.probePosition[1], data.boxMin[1], data.boxMax[1]);
							#endif

							half3 env1 = Unity_GlossyEnvironment (UNITY_PASS_TEXCUBE_SAMPLER(unity_SpecCube1,unity_SpecCube0), data.probeHDR[1], glossIn);
							specular = lerp(env1, env0, blendLerp);
						}
						else
						{
							specular = env0;
						}
					#else
						specular = env0;
					#endif
				#endif

				return specular * occlusion;
			}

			inline UnityGI UnityGlobalIllumination_BleedAO (UnityGIInput data, half3 occlusion, half3 normalWorld, Unity_GlossyEnvironmentData glossIn)
			{
				UnityGI o_gi = UnityGI_Base_BleedAO(data, occlusion, normalWorld);
				o_gi.indirect.specular = UnityGI_IndirectSpecular_BleedAO(data, occlusion, glossIn);
				return o_gi;
			}

			inline void LightingStandard_GI_BleedAO (
				lightStandard s,
				UnityGIInput data,
				inout UnityGI gi)
			{
				Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(s.Smoothness, data.worldViewDir, s.Normal, lerp(unity_ColorSpaceDielectricSpec.rgb, s.Albedo, s.Metallic));
				gi = UnityGlobalIllumination_BleedAO(data, s.Occlusion, s.Normal, g);
			}

			inline void LightingStandard_GI (
				lightStandard s,
				UnityGIInput data,
				inout UnityGI gi)
			{
				Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(s.Smoothness, data.worldViewDir, s.Normal, lerp(unity_ColorSpaceDielectricSpec.rgb, s.Albedo, s.Metallic));
				gi = UnityGlobalIllumination(data, s.Occlusion, s.Normal, g);
			}


		ENDCG
		
		Pass 
        {
			NAME "OUTLINE"
			
			Cull Front
			
			CGPROGRAM
			
			#pragma vertex vert
			#pragma fragment frag
			
			float _Outline;
			fixed4 _OutlineColor;
			
			struct a2v 
            {
				float4 vertex : POSITION;
				float3 normal : NORMAL;
			}; 
			
			struct v2f 
            {
			    float4 pos : SV_POSITION;
			};
			
			v2f vert (a2v v) 
            {
				v2f o;
				
				float4 pos = mul(UNITY_MATRIX_MV, v.vertex); 
				float3 normal = mul((float3x3)UNITY_MATRIX_IT_MV, v.normal);  
				normal.z = - 0.5;
				pos = pos + float4(normalize(normal), 0) * _Outline;
				o.pos = mul(UNITY_MATRIX_P, pos);
				
				return o;
			}
			
			float4 frag(v2f i) : SV_Target 
            { 
				return float4(_OutlineColor.rgb, 1);               
			}
			ENDCG
		}

        Pass 
		{
			Tags { "LightMode"="ForwardBase" }
			
			Cull Back
		
			CGPROGRAM
		
			#pragma vertex vert
			#pragma fragment frag
			
			
			#pragma multi_compile_fwdbase
			#pragma multi_compile_fog

			// #pragma shader_feature BLEEDING_AO

			// #define FOG_LINEAR
			#define UNITY_INSTANCED_SH
			#define UNITY_INSTANCED_LIGHTMAPSTS

			#define INTERNAL_DATA
			#define WorldReflectionVector(data,normal) data.worldRefl
			#define WorldNormalVector(data,normal) normal

			struct v2f 
            {
				float4 pos : POSITION;
				half2 uv_Albedo : TEXCOORD0;
                half2 uv_Normal : TEXCOORD1;
				half2 uv_Light : TEXCOORD9;
				SHADOW_COORDS(2)
				UNITY_FOG_COORDS(10)
                half3 sh : TEXCOORD3;
                float3 worldPos : TEXCOORD4;
                float3 worldNormal : TEXCOORD8;
                float4 TtoW0 : TEXCOORD7;
                float4 TtoW1 : TEXCOORD5;
                float4 TtoW2 : TEXCOORD6;
				#ifdef LIGHTMAP_ON
                    float4 lmap : TEXCOORD11;
                #endif
			};
			
			v2f vert (appdata_full v) 
            {
				v2f o;
				UNITY_INITIALIZE_OUTPUT(v2f, o);
				
				o.pos = UnityObjectToClipPos( v.vertex);
                o.uv_Albedo = TRANSFORM_TEX(v.texcoord, _MainTex);
                o.uv_Normal = TRANSFORM_TEX(v.texcoord, _BumpMap);
				o.uv_Light = TRANSFORM_TEX(v.texcoord, _Lightmap);//r = AO, g = roughness, b = metalic

                float3 worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                float3 worldNormal = UnityObjectToWorldNormal(v.normal);
                float3 worldTangent = UnityObjectToWorldDir(v.tangent.xyz);
                float3 worldBinormal = cross(worldNormal, worldTangent) * v.tangent.w * unity_WorldTransformParams.w;

                o.worldPos.xyz = worldPos;
                o.worldNormal = worldNormal;
                o.TtoW0 = float4(worldTangent.x, worldBinormal.x, worldNormal.x, worldPos.x);
                o.TtoW1 = float4(worldTangent.y, worldBinormal.y, worldNormal.y, worldPos.y);
                o.TtoW2 = float4(worldTangent.z, worldBinormal.z, worldNormal.z, worldPos.z);
                // o.sh = ShadeSH9 (half4 (worldNormal, 1));

				#ifdef LIGHTMAP_ON
                    o.lmap.xy = v.texcoord1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
                #endif
				
				//   SH/ambient and vertex lights
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
				TRANSFER_SHADOW(o);
				UNITY_TRANSFER_LIGHTING(o,v.texcoord1.xy); // pass shadow and, possibly, light cookie coordinates to pixel shader
				// #ifdef FOG_COMBINED_WITH_TSPACE
				// 	UNITY_TRANSFER_FOG_COMBINED_WITH_TSPACE(o,o.pos); // pass fog coordinates to pixel shader
				// #elif defined (FOG_COMBINED_WITH_WORLD_POS)
				// 	UNITY_TRANSFER_FOG_COMBINED_WITH_WORLD_POS(o,o.pos); // pass fog coordinates to pixel shader
				// #else
					UNITY_TRANSFER_FOG(o,o.pos); // pass fog coordinates to pixel shader
				// #endif

				return o;
			}
			
			half4 frag(v2f i) : SV_Target 
            { 
				float3 worldPos = i.worldPos;
				half3 worldNormal = normalize(i.worldNormal);
				half3 worldLightDir = normalize(UnityWorldSpaceLightDir(i.worldPos));
				half3 worldViewDir = normalize(UnityWorldSpaceViewDir(i.worldPos));

				lightStandard o;
				UNITY_INITIALIZE_OUTPUT(lightStandard, o);
                o.Normal = UnpackNormal(tex2D(_BumpMap, i.uv_Normal.xy));
                o.Normal.xy *= _BumpScale;
                o.Normal.z = sqrt(1.0 - saturate(dot(o.Normal.xy, o.Normal.xy)));
                o.Normal = normalize(half3(dot(i.TtoW0.xyz, o.Normal), dot(i.TtoW1.xyz, o.Normal), dot(i.TtoW2.xyz, o.Normal)));
				o.Albedo = tex2D (_MainTex, i.uv_Albedo).rgb * _Color.rgb;
				o.Specular = (_SpecularColor).xxx;
                o.Smoothness = _Smoothness;
				o.Metallic = _Metallic;
                o.Alpha = 1.0;

			#ifdef BLEEDING_AO 
				o.Occlusion = lerp(1, tex2D(_Lightmap, i.uv_Light).r, _AOThresh );
				float regularAO = lerp(1, tex2D(_Lightmap, i.uv_Light).r, _AOThresh );
				o.Occlusion = pow(o.Albedo, 1- regularAO); //use albedo
			#else
				o.Occlusion = lerp(1, tex2D(_Lightmap, i.uv_Light).r, _AOThresh );
			#endif

				// o.Occlusion = pow(_AOColor, 1- regularAO); //use single color
				// return float4o.Occlusion.rrrr;
				// return float4(o.Occlusion, 1);
                o.Emission = tex2D(_Lightmap, i.uv_Light).a;
				// half3 ambient = i.sh;
				UNITY_LIGHT_ATTENUATION(atten, i, i.worldPos);

				                // Setup lighting environment
                UnityGI gi;
                UNITY_INITIALIZE_OUTPUT(UnityGI, gi);
                gi.indirect.diffuse = 0;
                gi.indirect.specular = 0;
                gi.light.color = _LightColor0.rgb;
                gi.light.dir = worldLightDir;
                // Call GI (lightmaps/SH/reflections) lighting function
                UnityGIInput giInput;
                UNITY_INITIALIZE_OUTPUT(UnityGIInput, giInput);
                giInput.light = gi.light;
                giInput.worldPos = worldPos;
                giInput.worldViewDir = worldViewDir;
                giInput.atten = atten;

                #if defined (LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
                    giInput.lightmapUV = i.lmap;
                #else
                    giInput.lightmapUV = 0.0;
                #endif
                #if UNITY_SHOULD_SAMPLE_SH && !UNITY_SAMPLE_FULL_SH_PER_PIXEL
                    giInput.ambient = i.sh;
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
				
			#ifdef BLEEDING_AO
				LightingStandard_GI_BleedAO(o, giInput, gi);
			#else
				LightingStandard_GI(o, giInput, gi);
			#endif
                
			//Lighting Standard()
				o.Normal = normalize(o.Normal);

				half metalic = tex2D(_Lightmap, i.uv_Light).b * o.Metallic;

				half oneMinusReflectivity;
				half3 specColor = _SpecularColor;
				o.Albedo = DiffuseAndSpecularFromMetallic (o.Albedo, metalic, /*out*/ specColor, /*out*/ oneMinusReflectivity);
		
				// shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
				// this is necessary to handle transparency in physically correct way - only diffuse component gets affected by alpha
				half outputAlpha;
				o.Albedo = PreMultiplyAlpha (o.Albedo, o.Alpha, oneMinusReflectivity, /*out*/ outputAlpha);

			//important vector
				// half3 halfDir = normalize(worldLightDir + worldViewDir);
				float3 halfDir = Unity_SafeNormalize (float3(gi.light.dir) + worldViewDir);

				#define UNITY_HANDLE_CORRECTLY_NEGATIVE_NDOTV 0

				#if UNITY_HANDLE_CORRECTLY_NEGATIVE_NDOTV
					// The amount we shift the normal toward the view vector is defined by the dot product.
					half shiftAmount = dot(o.Normal, worldViewDir);
					o.Normal = shiftAmount < 0.0f ? o.Normal + worldViewDir * (-shiftAmount + 1e-5f) : o.Normal;
					// A re-normalization should be applied here but as the shift is small we don't do it to save ALU.
					//normal = normalize(normal);
					float NdotV = saturate(dot(o.Normal, worldViewDir)); // TODO: this saturate should no be necessary here
				#else
					half NdotV = abs(dot(o.Normal, worldViewDir));    // This abs allow to limit artifact
				#endif
			//Controllable NdotL
				half NdotL =  dot(o.Normal, gi.light.dir);// * _ShadowRange;
				// NdotL = NdotL * (_ShadingSoftness * 5) + _ShadowRange;
				float lightIntensity = smoothstep(0, 0.01, (NdotL * _ShadingSoftness + _ShadowRange) * atten);
				// float lightIntensity = smoothstep(0, 0.01, (NdotL) * atten);
				// NdotL = saturate(NdotL)* atten;
				half4 controlColor = lerp(_shadowColor, _brightColor, lightIntensity); 

				half NdotH = dot(o.Normal, halfDir);

				// float perceptualRoughness = g.roughness;
				// float nl = (NdotL * 0.5 + 0.5) * atten;
				
				// half fresnel = _Fresnel + (1 - _Fresnel) * pow(1 - nv, _FresnelIntensity);
				
			//fresnel term
				float3 reflDir = reflect (worldViewDir, o.Normal);
				float rimintensity = reflDir * pow(NdotL, _RimThreshold);
				// float toomRim = tex2D(_Lightmap, i.uv_Light).g *smoothstep(_RimAmount - 0.01, _RimAmount + 0.01, rimintensity);
				float toomRim = smoothstep(_RimAmount - 0.01, _RimAmount + 0.01, rimintensity);
				float4 Fr = toomRim * _RimColor;

				//keep physical correct
				half2 rlPow4AndFresnelTerm = Pow4 (float2(dot(reflDir, gi.light.dir), 1 - NdotV));  // use R.L instead of N.H to save couple of instructions
				half rlPow4 = rlPow4AndFresnelTerm.x; // power exponent must match kHorizontalWarpExp in NHxRoughness() function in GeneratedTextures.cpp
				half fresnelTerm = rlPow4AndFresnelTerm.y;
				// float Fr = pow(fresnelTerm, _Fresnel);
			//diffuse term
				half3 diffuseTerm = _LightColor0.rgb * o.Albedo * controlColor;
			if (_GI > 0)
			// 	// * indirect.diffuse may have negative ecfect 
				diffuseTerm += gi.indirect.diffuse * o.Albedo * (_GIIntensity/2);
			
				// return half4(diffuse.rgb,1);
			// Specular term
				half perceptualRoughness = SmoothnessToPerceptualRoughness (o.Smoothness);
				// half roughness_pre = PerceptualRoughnessToRoughness(perceptualRoughness);
				half roughness = tex2D(_Lightmap, i.uv_Light).g * step(0.0001, o.Smoothness);
				
				half w = fwidth(NdotH) * 2.0;
				half3 specularTerm = _SpecularColor * lerp(0, 1, smoothstep(-w, w, NdotH + _SpecularScale - 1)) * roughness;
				// half specularTerm = tex2D(_Lightmap, half2(rlPow4, SmoothnessToPerceptualRoughness(o.Smoothness))).g * step(0.0001, o.Smoothness);
				// float specularTerm = smoothstep(0.005, 0.01, pow(NdotH * lightIntensity, _SpecularScale));
			//Emissive	
				// float3 emission = (pow((1.0 - saturate(NdotV)) , _EmissiveIntensity) * _EmissiveColor).rgb * o.Emission.rrr;
				float3 emission = o.Emission * _EmissiveColor * _EmissiveIntensity;
			//Grazing Term
				half grazingTerm = saturate(roughness + (1-oneMinusReflectivity));

			// surfaceReduction = Int D(NdotH) * NdotH * Id(NdotL>0) dH = 1/(roughness^2+1)
				half surfaceReduction;
				#   ifdef UNITY_COLORSPACE_GAMMA
						surfaceReduction = 1.0-0.28*roughness*perceptualRoughness;      // 1-0.28*x^3 as approximation for (1/(x^4+1))^(1/2.2) on the domain [0;1]
				#   else
						surfaceReduction = 1.0 / (roughness*roughness + 1.0);           // fade \in [0.5;1]
				#   endif
			//Final
				//add giInput.ambient can be cracked by realtime gi
				half4 c = half4(diffuseTerm + specularTerm* gi.light.color + gi.indirect.specular * lerp (specColor, grazingTerm, fresnelTerm), o.Alpha);
				// half4 c = half4(giInput.ambient + diffuseTerm + specularTerm * gi.light.color + gi.indirect.specular * lerp (specColor, grazingTerm, fresnelTerm), o.Alpha);
				// half4 c = half4((diffuseTerm + specularTerm ).rgb, o.Alpha);
				// return half4 (diffuseTerm + specularTerm, 1.0);
			// if (_GI < 1)
				// c.rgb += giInput.ambient;

				c.rgb += emission;
			if (_isFresnel > 0)
				c += Fr * (atten).rrrr + Fr * (1 - atten).rrrr * 0.1;

			//Final Color Grading
			//apply brightness
				c.rgb *= _Brightness;

			//apply saturations
				half luminance = 0.2125 * o.Albedo.r + 0.7154 * o.Albedo.g + 0.0721 * o.Albedo.b;
				half3 luminanceColor = half3(luminance, luminance, luminance);
				c.rgb = lerp(luminanceColor, c, _Saturation);
			
			//apply contrast
				half3 avgColor = half3(0.5,0.5,0.5);
				c.rgb = lerp(avgColor, c, _Contrast);

				// UNITY_APPLY_FOG(_unity_fogCoord, c);
				// UNITY_OPAQUE_ALPHA(c.a);
				UNITY_APPLY_FOG(i.fogCoord, c);//apply fog
				return c;
			}
			ENDCG
		}
	}
	FallBack "Standard"
}
