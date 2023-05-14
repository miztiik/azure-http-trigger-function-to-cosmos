
param deploymentParams object
param tags object = resourceGroup().tags

param cosmosDbParams object
// param cosmosAccountName string
// param cosmosDatabaseName string
// param cosmosCollectionName string




// Create CosmosDB Account
resource r_cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' = {
  name: '${cosmosDbParams.cosmosDbNamePrefix}-db-account-${deploymentParams.global_uniqueness}'
  location: deploymentParams.location
  kind: 'GlobalDocumentDB'
  tags: tags
  properties: {
    publicNetworkAccess: 'Enabled'
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: true
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: deploymentParams.location
        isZoneRedundant: false
      }
    ]
    
    backupPolicy: {
      type: 'Continuous'
    }
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
  }
}

// Create CosmosDB Database
var databaseName = '${cosmosDbParams.cosmosDbNamePrefix}-db-${deploymentParams.global_uniqueness}'

resource r_cosmosDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-06-15' = {
  parent: r_cosmosDbAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

var containerName = '${cosmosDbParams.cosmosDbNamePrefix}-container-${deploymentParams.global_uniqueness}'

// Create CosmosDB Container
resource r_cosmosDbContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-08-15' = {
  name: containerName
  parent: r_cosmosDb
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          '/id'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/_etag/?'
          }
        ] 
      }
      conflictResolutionPolicy: {
        mode: 'LastWriterWins'
        conflictResolutionPath: '/_ts'
      }
    }
  }
}


// Outputs
output cosmosDbAccountName string = r_cosmosDbAccount.name
output cosmosDbName string = r_cosmosDb.name
output cosmosDbContainerName string = r_cosmosDbContainer.name

