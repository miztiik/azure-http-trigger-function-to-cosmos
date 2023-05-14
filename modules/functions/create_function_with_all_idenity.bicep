param deploymentParams object
param funcParams object
param tags object = resourceGroup().tags
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
    // type: 'SystemAssigned'
    type: 'SystemAssigned, UserAssigned'
      userAssignedIdentities: {
        '${r_userManagedIdentity.id}': {}
      }
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
    FUNCTIONS_WORKER_RUNTIME: 'python'
    FUNCTIONS_EXTENSION_VERSION: '~4'
    // ENABLE_ORYX_BUILD: 'true'
    // SCM_DO_BUILD_DURING_DEPLOYMENT: 'true'
    WAREHOUSE_STORAGE: 'DefaultEndpointsProtocol=https;AccountName=${saName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${r_sa.listKeys().keys[0].value}'
    WAREHOUSE_STORAGE_CONTAINER: blobContainerName
    SUBSCRIPTION_ID: subscription().subscriptionId
    RESOURCE_GROUP: resourceGroup().name
    COSMOS_DB_URL: r_cosmodbAccnt.properties.documentEndpoint
    COSMOS_DB_NAME: cosmosDbName
    COSMOS_DB_CONTAINER_NAME: cosmosDbContainerName

    // COSMOS_DB_KEY: r_cosmodbAccnt.listKeys().primaryMasterKey
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
        // {
        //   "name": "blobTrigger",
        //   "type": "timerTrigger",
        //   "direction": "in",
        //   "schedule": "0 0 * * * *",
        //   "connnection": "AzureWebJobsStorage",
        //   "path": "blob/{test}"
        //  },
        // {
        //   authLevel: 'anonymous'
        //   type: 'httpTrigger'
        //   direction: 'in'
        //   name: 'req'
        //   webHookType: 'genericJson'
        //   methods: [
        //     'get'
        //     'post'
        //   ]
        // }
        {
          name: 'miztProc'
          type: 'blob'
          direction: 'in'
          path: '{data.url}'
          connection: 'WAREHOUSE_STORAGE'
          // datatype: 'binary'
        }
        {
          type: 'eventGridTrigger'
          name: 'event'
          direction: 'in'
        }
        {
          type: 'blob'
          direction: 'out'
          name: 'outputBlob'
          // path: '${blobContainerName}/processed/{DateTime}_{rand-guid}_{data.eTag}.json'
          path: '${blobContainerName}/processed/{DateTime}_{data.eTag}.json'
          connection: 'WAREHOUSE_STORAGE'
        }
        // {
        //   name: '$return'
        //   direction: 'out'
        //   type: 'http'
        // }
        // {
        //   type: 'queue'
        //   name: 'outputQueueItem'
        //   queueName: 'goodforstage1'
        //   connection: 'StorageAccountMain'
        //   direction: 'out'
        // }
        // {
        //   type: 'queue'
        //   name: 'outputQueueItemWithError'
        //   queueName: 'badforstage1'
        //   connection: 'StorageAccountMain'
        //   direction: 'out'
        // }
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




// Add permissions to the custom identity to write to the blob storage
// Azure Built-In Roles Ref: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles
var storageBlobDataContributorRoleDefinitionId = resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')

resource r_storageBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name:  guid('r_storageBlobDataContributorRoleAssignment', r_blob_Ref.id, storageBlobDataContributorRoleDefinitionId)
  scope: r_blob_Ref
  properties: {
    roleDefinitionId: storageBlobDataContributorRoleDefinitionId
    principalId: r_userManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}


param blobOwnerRoleId string = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'

var blobPermsConditionStr= '((!(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read\'}) AND !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write\'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals \'${blobContainerName}\'))'

resource r_blob_Ref 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' existing = {
  name: '${saName}/default/${blobContainerName}'
}


// Refined Scope with conditions
// https://learn.microsoft.com/en-us/azure/templates/microsoft.authorization/roleassignments?pivots=deployment-language-bicep

resource r_attachBlobOwnerPermsToRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid('r_attachBlobOwnerPermsToRole', r_userManagedIdentity.id, blobOwnerRoleId)
  scope: r_blob_Ref
  properties: {
    description: 'Blob Owner Permission to ResourceGroup scope'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', blobOwnerRoleId)
    principalId: r_userManagedIdentity.properties.principalId
    conditionVersion: '2.0'
    condition: blobPermsConditionStr
    principalType: 'ServicePrincipal'
    // https://learn.microsoft.com/en-us/azure/role-based-access-control/troubleshooting?tabs=bicep#symptom---assigning-a-role-to-a-new-principal-sometimes-fails
  }
}

// Get Cosmos DB Account Ref
resource r_cosmodbAccnt 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' existing = {
  name: cosmosDbAccountName
}

// Create a custom role definition for Cosmos DB
resource r_cosmodb_customRoleDef 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2023-04-15' = {
  parent: r_cosmodbAccnt
  name:  guid('r_cosmodb_customRole', r_userManagedIdentity.id, r_cosmodbAccnt.id)
  properties: {
    roleName: 'Miztiik Custom Role to read w Cosmos DB1'
    type: 'CustomRole'
    assignableScopes: [
      r_cosmodbAccnt.id
    ]
    permissions: [
      {
        dataActions: [
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/executeQuery'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/readChangeFeed'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/executeStoredProcedure'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/manageConflicts'
        ]
      }
    ]
  }
}

// Assign the custom role to the user-assigned managed identity
var cosmosDbDataContributorRoleDefinitionId = resourceId('Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', r_cosmodbAccnt.name, '00000000-0000-0000-0000-000000000002')
resource r_customRoleAssignmentToSysIdentity 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2021-04-15' = {
  name:  guid(r_userManagedIdentity.id, r_cosmodbAccnt.id, cosmosDbDataContributorRoleDefinitionId)
  parent: r_cosmodbAccnt
  properties: {
    roleDefinitionId: r_cosmodb_customRoleDef.id
    scope: r_cosmodbAccnt.id
    principalId: r_userManagedIdentity.properties.principalId
  }
}

resource r_customRoleAssignmentToUsrIdentity 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2021-04-15' = {
  name:  guid(r_userManagedIdentity.id, r_cosmodbAccnt.id, 'r_customRoleAssignmentToUsrIdentity')
  parent: r_cosmodbAccnt
  properties: {
    roleDefinitionId: r_cosmodb_customRoleDef.id
    scope: r_cosmodbAccnt.id
    principalId: r_userManagedIdentity.properties.principalId
  }
}



var roleAssignmentId = guid('sql-role-assignment', resourceGroup().id, r_cosmodbAccnt.id)

// Create Cosmos DB Role Assignment for Function App
resource r_dbRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2022-08-15' = {
  name: roleAssignmentId
  parent: r_cosmodbAccnt
  properties: {
    principalId: r_fnApp.identity.principalId
    roleDefinitionId: '/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.DocumentDB/databaseAccounts/${r_cosmodbAccnt.name}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: r_cosmodbAccnt.id
  }
}

// This is for managing CosmoDBs - Not Data Plane Operations
// Assigned to Function App Managed Identity
var cosmosContributorRoleDefId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5bd9cd88-fe45-4216-938b-f97437e15450')
resource r_cosmosFnAppAadRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(r_cosmodbAccnt.id, r_fnApp.name, cosmosContributorRoleDefId)
  scope: r_cosmodbAccnt
  properties: {
    principalId: r_fnApp.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: cosmosContributorRoleDefId
  }
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

// Function Outputs
// output fnName string = r_fn_1.name
output fnIdentity string = r_fnApp.identity.principalId
output fnAppUrl string = r_fnApp.properties.defaultHostName
output fnUrl string = r_fnApp.properties.defaultHostName
