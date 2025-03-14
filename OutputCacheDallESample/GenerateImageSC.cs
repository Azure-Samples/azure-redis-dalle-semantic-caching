﻿using Azure.AI.OpenAI;
using Azure;
using Redis.OM;
using Redis.OM.Vectorizers;
using Microsoft.AspNetCore.DataProtection.KeyManagement;
using OpenAI.Images;
using Azure.Identity;

namespace OutputCacheDallESample
{
    public static class GenerateImageSC
    {
        private static RedisConnectionProvider _provider;
        public static async Task GenerateImageSCAsync(HttpContext context, string _prompt, IConfiguration _config)
        {
            string imageURL;

            string endpoint = _config["AZURE_OPENAI_ENDPOINT"];
            string key = _config["apiKey"];

            _provider = new RedisConnectionProvider(_config["SemanticCacheAzureProvider"]);
            var cache = _provider.AzureOpenAISemanticCache(_config["apiKey"], _config["AOAIResourceName"], _config["AOAIEmbeddingDeploymentName"], 1536);

            if (cache.GetSimilar(_prompt).Length > 0)
            {
                imageURL = cache.GetSimilar(_prompt)[0];
                await context.Response.WriteAsync("<!DOCTYPE html><html><body> " +
                                                  $"<img src=\"{imageURL}\" alt=\"AI Generated Picture {_prompt}\" width=\"460\" height=\"345\">" +
                                                  " </body> </html>");
            }
            else 
            {
                // AzureOpenAIClient client = new(new Uri(endpoint), new AzureKeyCredential(key));
                AzureOpenAIClient client = new(new Uri(endpoint), new DefaultAzureCredential());

                ImageClient imageClient = client.GetImageClient("dall-e-3");
                GeneratedImage generatedImage = await imageClient.GenerateImageAsync(_prompt, new ImageGenerationOptions() {
                    Size = GeneratedImageSize.W1024xH1024
                });

                // Image Generations responses provide URLs you can use to retrieve requested images
                imageURL = generatedImage.ImageUri.AbsoluteUri;

                await cache.StoreAsync(_prompt, imageURL);

                await context.Response.WriteAsync("<!DOCTYPE html><html><body> " +
                $"<img src=\"{imageURL}\" alt=\"AI Generated Picture {_prompt}\" width=\"460\" height=\"345\">" +
                " </body> </html>");
            }

            
        }
    }
}
