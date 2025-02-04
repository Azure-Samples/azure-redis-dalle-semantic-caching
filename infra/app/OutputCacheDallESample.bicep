param name string
param location string = resourceGroup().location
param tags object = {}
param identityName string
param containerRegistryName string
param containerAppsEnvironmentName string
param applicationInsightsName string
param exists bool
param openAiSku object = {
  name:'S0'
}

var embeddingDeploymentCapacity = 30
var redisPort = 10000

var openai_deployments = [

  {
    name: 'text-embedding-ada-002'
	  model_name: '${name}-textembedding'
    version: '2'
    raiPolicyName: 'Microsoft.Default'
    sku_capacity: embeddingDeploymentCapacity
    sku_name: 'Standard'
  }

  {
    name: 'dall-e-3'
	  model_name: 'dall-e-3'
    version: '3.0'
    raiPolicyName: 'Microsoft.Default'
    sku_capacity: 1
    sku_name: 'Standard'
  }

]

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' existing = {
  name: containerRegistryName
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-04-01-preview' existing = {
  name: containerAppsEnvironmentName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: containerRegistry
  name: guid(subscription().id, resourceGroup().id, identity.id, 'acrPullRole')
  properties: {
    roleDefinitionId:  subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalType: 'ServicePrincipal'
    principalId: identity.properties.principalId
  }
}

module fetchLatestImage '../modules/fetch-container-image.bicep' = {
  name: '${name}-fetch-image'
  params: {
    exists: exists
    name: name
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: '${substring(name, 0, 15)}-keyvault'
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: subscription().tenantId
        objectId: app.identity.principalId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
  }
}

resource applicationinsights__connectionstring 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'applicationinsights--connectionstring'
  properties: {
    value: applicationInsights.properties.ConnectionString
  }
}

resource apiKey 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'apiKey'
  properties:{
    value: cognitiveAccount.listKeys().key1
  }
}

resource azure__openai__endpoint 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'azure--openai--endpoint'
  properties:{
    value: cognitiveAccount.properties.endpoint
  }
}

resource aoai__resourcename 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'aoai--resourcename'
  properties:{
    value: cognitiveAccount.name
  }
}

resource aoai__embedding__deploymentname 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'aoai--embedding--deploymentname'
  properties: {
    value: '${name}-textembedding'
  }
}

resource api__url 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'api--url'
  properties:{
    value: '${cognitiveAccount.properties.endpoint}openai/deployments/Dalle3/images/generations?api-version=2024-02-01'
  }
}

resource redis__cache__connection 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'redis--cache--connection'
  properties: {
    value: '${redisCache.properties.hostName}:10000,password=${redisdatabase.listKeys().primaryKey},ssl=True,abortConnect=False'
  }
}

resource semantic__cache__azure__provider 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: keyVault
  name: 'semantic--cache--azure--provider'
  properties: {
    value: 'rediss://:${redisdatabase.listKeys().primaryKey}@${redisCache.properties.hostName}:10000'
  }
}

resource app 'Microsoft.App/containerApps@2024-03-01' = {
  name: name
  location: location
  tags: union(tags, {'azd-service-name':  'OutputCacheDallESample' })
  dependsOn: [ acrPullRole]
  identity: {
    type: 'UserAssigned, SystemAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress:  {
        external: true
        targetPort: 8080
        transport: 'auto'
      }
      registries: [
        {
          server: '${containerRegistryName}.azurecr.io'
          identity: identity.id
        }
      ]
      secrets: [
        {
          name: 'applicationinsights--connectionstring'
          value: applicationInsights.properties.ConnectionString
        }
        {
          name: 'api--key'
          value: cognitiveAccount.listKeys().key1
        }
        {
          name: 'azure--openai--endpoint'
          value: cognitiveAccount.properties.endpoint
        }
        {
          name: 'aoai--resourcename'
          value: cognitiveAccount.name
        }
        {
          name: 'aoai--embedding--deploymentname'
          value: '${name}-textembedding'
        }
        {
          name: 'api--url'
          value: '${cognitiveAccount.properties.endpoint}openai/deployments/Dalle3/images/generations?api-version=2024-02-01'
        }
        {
          name: 'redis--cache--connection'
          value: '${redisCache.properties.hostName}:10000,password=${redisdatabase.listKeys().primaryKey},ssl=True,abortConnect=False'
        }
        {
          name: 'semantic--cache--azure--provider'
          value: 'rediss://:${redisdatabase.listKeys().primaryKey}@${redisCache.properties.hostName}:10000'
        }
      ]
    }
    template: {
      containers: [
        {
          image: fetchLatestImage.outputs.?containers[?0].?image ?? 'cathyxwang/outputcachedallesample:latest'
          name: 'main'
          env: [
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              secretRef: 'applicationinsights--connectionstring'
            }
            {
              name: 'PORT'
              value: '8080'
            }
            {
              name: 'apiKey'
              secretRef: 'api--key'
            }
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              secretRef: 'azure--openai--endpoint'
            }
            {
              name: 'AOAIResourceName'
              secretRef: 'aoai--resourcename'
            }
            {
              name: 'AOAIEmbeddingDeploymentName'
              secretRef: 'aoai--embedding--deploymentname'
            }
            {
              name: 'apiUrl'
              secretRef: 'api--url'
            }
            {
              name: 'RedisCacheConnection'
              secretRef: 'redis--cache--connection'
            }
            {
              name:'SemanticCacheAzureProvider'
              secretRef: 'semantic--cache--azure--provider'
            }
          ]
          resources: {
            cpu: json('1.0')
            memory: '2.0Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 10
      }
    }
  }
}

//azure open ai resource
resource cognitiveAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: '${name}-csaccount'
  location: location
  tags: tags
  kind: 'OpenAI'
  properties: {
    customSubDomainName: '${name}-csaccount'
    publicNetworkAccess: 'Enabled'
    apiProperties: {
      enableDallE: true
    }
  }
  sku: openAiSku
}

@batchSize(1)
resource model 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = [for deployment in openai_deployments: {
  name: deployment.model_name
  parent: cognitiveAccount
  sku: {
	name: deployment.sku_name
	capacity: deployment.sku_capacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: deployment.name
      version: deployment.version
    }
    raiPolicyName: deployment.raiPolicyName
  }
}]

resource openai_CognitiveServicesOpenAIUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cognitiveAccount.id, identity.id, subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'))
  properties: {
    principalId: identity.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
    principalType: 'ServicePrincipal'
  }
  scope: cognitiveAccount
}

resource openai_CognitiveServicesOpenAIContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cognitiveAccount.id, app.id, subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442'))
  properties: {
    principalId: app.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442')
    principalType: 'ServicePrincipal'
  }
  scope: cognitiveAccount
}

//azure cache for redis resource
resource redisCache 'Microsoft.Cache/redisEnterprise@2024-02-01' = {
  location:location
  name: '${name}-rediscache'
  sku:{
    capacity:2
    name: 'Enterprise_E1'
  }
}
resource redisdatabase 'Microsoft.Cache/redisEnterprise/databases@2024-02-01' = {
  name: 'default'
  parent: redisCache
  properties:{
    evictionPolicy:'NoEviction'
    clusteringPolicy:'EnterpriseCluster'
    modules:[
      {
        name: 'RediSearch'
      }
      {
        name:'RedisJSON'
      }
    ]
    port: redisPort
  }
}

output defaultDomain string = containerAppsEnvironment.properties.defaultDomain
output name string = app.name
output uri string = 'https://${app.properties.configuration.ingress.fqdn}'
output id string = app.id
