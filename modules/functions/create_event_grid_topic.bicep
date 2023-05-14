param deploymentParams object
param funcParams object
// param funcName string
param funcAppName string

param saName string
param blobContainerName string

param tags object = resourceGroup().tags

// Get Storage Account Reference
resource r_sa 'Microsoft.Storage/storageAccounts@2021-06-01' existing = {
  name: saName
}

var funcName = '${funcParams.funcNamePrefix}-consumer-fn'

resource r_fnApp 'Microsoft.Web/sites@2021-02-01' existing = {
  name: funcAppName
}

// Reference an existing function within the function app
resource r_fn_1 'Microsoft.Web/sites/functions@2021-02-01' existing = {
  parent: r_fnApp
  name: funcName
}


// Create Event Grid Subscription with Filter
// Event Grid topic
// resource r_eventGrid_topic 'Microsoft.EventGrid/topics@2022-06-15' = {
  resource r_eventGrid_system_topic 'Microsoft.EventGrid/systemTopics@2022-06-15' = {
    name: '${funcParams.funcNamePrefix}-eventGrid-Topic-${deploymentParams.global_uniqueness}'
    location: deploymentParams.location
    tags: tags
    identity: {
      type: 'None'
    }
    properties: {
      source: r_sa.id
      topicType: 'microsoft.storage.storageaccounts'
      // dataResidencyBoundary: 'WithinRegion'
      // inputSchema: 'CloudEventSchemaV1_0'
      // publicNetworkAccess: 'Enabled'
    }
  }
 
  // Blob Change Log Subscription with filter
  resource r_fn_1_eventGrid_subscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2022-06-15' = {
    parent: r_eventGrid_system_topic
    name: '${funcParams.funcNamePrefix}-blob-events-subscription-${deploymentParams.global_uniqueness}'
    properties: {
      eventDeliverySchema: 'CloudEventSchemaV1_0'
      destination: {
        endpointType: 'AzureFunction'
            properties: {
              resourceId: r_fn_1.id
              // resourceId: resourceId('Microsoft.Web/Sites/functions', '${funcAppName}', '${funcName}')
              maxEventsPerBatch: 1
            preferredBatchSizeInKilobytes: 64
            }
      }
      filter: {
        subjectBeginsWith: '/blobServices/default/containers/${blobContainerName}/blobs/source'
        subjectEndsWith: '.json'
            includedEventTypes: [ 
              'Microsoft.Storage.BlobCreated'
              // 'Microsoft.Storage.BlobDeleted'
            ]
      }    
      retryPolicy: {
        maxDeliveryAttempts: 30
        eventTimeToLiveInMinutes: 1440
      }
    }
  }
  

  // /subscriptions/1ac6fdb8-61a9-4e86-a871-1baff37cd9e3/resourceGroups/Miztiik_Enterprises_blob_trigger_function_user_identity_009/providers/Microsoft.Web/sites/store-backend-fnApp-009/functions/store-events-consumer-fn


  // [resourceId('Microsoft.Web/sites/functions', split(format('{0}-consumer-fn', parameters('funcParams').funcNamePrefix), '/')[0], split(format('{0}-consumer-fn', parameters('funcParams').funcNamePrefix), '/')[1])]
