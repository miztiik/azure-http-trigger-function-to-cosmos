param deploymentParams object
param funcParams object
param tags object
param logAnalyticsWorkspaceId string
param enableDiagnostics bool = true

param saName string
param funcSaName string

param blobContainerName string
param cosmosDbAccountName string
param cosmosDbName string
param cosmosDbContainerName string

// Get Storage Account Reference
resource r_sa 'Microsoft.Storage/storageAccounts@2021-06-01' existing = {
  name: saName
}
resource r_sa_1 'Microsoft.Storage/storageAccounts@2021-06-01' existing = {
  name: funcSaName
}

resource r_blob_Ref 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' existing = {
  name: '${saName}/default/${blobContainerName}'
}

// Create User-Assigned Identity
resource r_userManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${funcParams.funcNamePrefix}_identity_${deploymentParams.global_uniqueness}'
  location: deploymentParams.location
  tags: tags
}


resource r_fnHostingPlan 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: '${funcParams.funcAppPrefix}-fnPlan-${deploymentParams.global_uniqueness}'
  location: deploymentParams.location
  tags: tags
  kind: 'linux'
  sku: {
    // https://learn.microsoft.com/en-us/azure/azure-resource-manager/resource-manager-sku-not-available-errors
    name: funcParams.skuName
    tier: funcParams.funcHostingPlanTier
    family: 'Y'
  }
  properties: {
    reserved: true
  }
}

resource r_fnApp 'Microsoft.Web/sites@2021-03-01' = {
  name: '${funcParams.funcAppPrefix}-fnApp-${deploymentParams.global_uniqueness}'
  location: deploymentParams.location
  kind: 'functionapp,linux'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    reserved: true
    serverFarmId: r_fnHostingPlan.id
    clientAffinityEnabled: true
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|3.10' //az webapp list-runtimes --linux || az functionapp list-runtimes --os linux -o table
      // ftpsState: 'FtpsOnly'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
    }
  }
  dependsOn: [
    r_applicationInsights
  ]
}

resource r_fnApp_settings 'Microsoft.Web/sites/config@2021-03-01' = {
  parent: r_fnApp
  name: 'appsettings' // Reservered Name
  properties: {
    AzureWebJobsStorage: 'DefaultEndpointsProtocol=https;AccountName=${funcSaName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${r_sa_1.listKeys().keys[0].value}'
    WEBSITE_CONTENTAZUREFILECONNECTIONSTRING: 'DefaultEndpointsProtocol=https;AccountName=${funcSaName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${r_sa_1.listKeys().keys[0].value}'
    WEBSITE_CONTENTSHARE: toLower(funcParams.funcNamePrefix)
    APPINSIGHTS_INSTRUMENTATIONKEY: r_applicationInsights.properties.InstrumentationKey
    // APPINSIGHTS_INSTRUMENTATIONKEY: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=${keyVault::appInsightsInstrumentationKeySecret.name})'
    FUNCTIONS_WORKER_RUNTIME: 'python'
    FUNCTIONS_EXTENSION_VERSION: '~4'
    // ENABLE_ORYX_BUILD: 'true'
    // SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    AZURE_CLIENT_ID: r_userManagedIdentity.properties.clientId
    AZURE_TENANT_ID: r_userManagedIdentity.properties.tenantId
    WAREHOUSE_STORAGE: 'DefaultEndpointsProtocol=https;AccountName=${saName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${r_sa.listKeys().keys[0].value}'
    WAREHOUSE_STORAGE_CONTAINER: r_blob_Ref.name
    SUBSCRIPTION_ID: subscription().subscriptionId
    RESOURCE_GROUP: resourceGroup().name
    COSMOS_DB_URL: r_cosmodbAccnt.properties.documentEndpoint
    COSMOS_DB_NAME: cosmosDbName
    COSMOS_DB_CONTAINER_NAME: cosmosDbContainerName
    COSMOS_DB_KEY: r_cosmodbAccnt.listConnectionStrings().connectionStrings[0].connectionString
    // COSMOS_DB_KEY1: '@Microsoft.KeyVault(VaultName=${keyVault.name};SecretName=CosmosDbConnectionString)'
  }
  dependsOn: [
    r_sa
    r_sa_1
  ]
}

resource r_fnApp_logs 'Microsoft.Web/sites/config@2021-03-01' = {
  parent: r_fnApp
  name: 'logs'
  properties: {
    applicationLogs: {
      azureBlobStorage: {
        level: 'Error'
        retentionInDays: 10
        // sasUrl: ''
      }
    }
    httpLogs: {
      fileSystem: {
        retentionInMb: 100
        enabled: true
      }
    }
    detailedErrorMessages: {
      enabled: true
    }
    failedRequestsTracing: {
      enabled: true
    }
  }
  dependsOn: [
    r_fnApp_settings
  ]
}

// resource r_fn_1 'Microsoft.Web/sites/functions@2022-03-01' existing={
//   name: '${funcParams.funcNamePrefix}-consumer-fn'
// }

// Create Function


resource r_fn_1 'Microsoft.Web/sites/functions@2022-03-01' = {
  // name: '${funcParams.funcNamePrefix}-consumer-fn-${deploymentParams.global_uniqueness}'
  name: '${funcParams.funcNamePrefix}-consumer-fn'
  parent: r_fnApp
  properties: {
    // config_href: 'https://allotment-dev-uks-allotment-api.azurewebsites.net/admin/vfs/site/wwwroot/ConfirmEmail/function.json'
    invoke_url_template: 'https://${r_fnApp.name}.azurewebsites.net/api/sayhi'
    test_data: '{"method":"get","queryStringParams":[{"name":"miztiik-automation","value":"yes"}],"headers":[],"body":{"body":""}}'
    config: {
      disabled: false
      bindings: [
        {
          authLevel: 'anonymous'
          type: 'httpTrigger'
          direction: 'in'
          name: 'req'
          webHookType: 'genericJson'
          methods: [
            'get'
            'post'
          ]
        }
        {
          type: 'blob'
          direction: 'out'
          name: 'outputBlob'
          path: '${blobContainerName}/processed/{DateTime}_{rand-guid}.json'
          // path: '${blobContainerName}/processed/{DateTime}_{data.eTag}.json'
          connection: 'WAREHOUSE_STORAGE'
        }
        {
          type: 'cosmosDB'
          direction: 'out'
          name: 'doc'
          databaseName: '%COSMOS_DB_NAME%'
          collectionName: '%COSMOS_DB_CONTAINER_NAME%'
          createIfNotExists: true
          connectionStringSetting: 'COSMOS_DB_KEY'
        }
        {
          name: '$return'
          direction: 'out'
          type: 'http'
        }
      ]
    }
    files: {
      '__init__.py': loadTextContent('../../app/__init__.py')
      // 'function.json': replace(loadTextContent('../../app/function_code/function.json'),'BLOB_CONTAINER_NAME', blobContainerName)
    }
  }
  dependsOn: [
    r_fnApp_settings
  ]
}




// var hostJson = loadTextContent('host.json')
// resource zipDeploy 'Microsoft.Web/sites/extensions@2022-03-01' = {
//   parent: r_fnApp
//   name:  any('ZipDeploy')
//   properties: {
//     packageUri: 'https://github.com/miztiik/azure-create-functions-with-bicep/raw/main/app8.zip'
//       template: {
//         hostJson: json(hostJson)
//       }
//   }
// }

// module app_service_webjob_msdeploy 'nested/microsoft.web/sites/extensions.bicep' = {
//   name: 'app-service-webjob-msdeploy'
//   params: {
//     appServiceName: dnsNamePrefix
//     webJobZipDeployUrl: azAppServiceWebJobZipUri
//   }
//   dependsOn: [
//     app_service_deploy
//   ]
// }



// Get Cosmos DB Account Ref
resource r_cosmodbAccnt 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' existing = {
  name: cosmosDbAccountName
}

// Function App Binding
resource r_fnAppBinding 'Microsoft.Web/sites/hostNameBindings@2022-03-01' = {
  parent: r_fnApp
  name: '${r_fnApp.name}.azurewebsites.net'
  properties: {
    siteName: r_fnApp.name
    hostNameType: 'Verified'
  }
}

// Adding Application Insights
resource r_applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${funcParams.funcNamePrefix}-fnAppInsights-${deploymentParams.global_uniqueness}'
  location: deploymentParams.location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspaceId
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// Enabling Diagnostics for the Function
resource r_fnLogsToAzureMonitor 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (enableDiagnostics) {
  name: '${funcParams.funcNamePrefix}-logs-${deploymentParams.global_uniqueness}'
  scope: r_fnApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'FunctionAppLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

//FunctionApp Outputs
output fnAppName string = r_fnApp.name
output fnAppUrl string = r_fnApp.properties.defaultHostName

// Function Outputs
output fnName string = r_fn_1.name
output fnIdentity string = r_fnApp.identity.principalId
output fnUrl string = r_fnApp.properties.defaultHostName
