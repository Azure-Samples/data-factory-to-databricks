@description('Location of the data factory.')
param location string = resourceGroup().location

@description('The administrator username of the SQL logical server.')
param administratorLogin string = 'myadminname'

@description('The administrator password of the SQL logical server.')
@secure()
param administratorLoginPassword string = newGuid()

@description('The object id of the previous user')
param userObjectId string

@description('The tenant id of the previous user')
param userTenantId string

@description('The username that is deploying, the databricks workpace of the user will have the notebook and The Microsoft Entra ID user to be database admin')
param username string

@description('Specifies the Azure Active Directory tenant ID that should be used for authenticating requests to the key vault. Get it by using Get-AzSubscription cmdlet.')
param tenantId string = subscription().tenantId

param secretsExpirationDate int

// --- Variables
var uniqueName = uniqueString(resourceGroup().id)
@description('Data Factory Name')
var dataFactoryName = 'datafactory-${uniqueName}'
@description('The name of the Azure Databricks workspace to create.')
var workspaceName = 'databricks-workpace-${uniqueName}'
@description('The name of the Azure Data Lake Store to create.')
var datalakeStoreName = 'datalake${uniqueName}'
@description('The name of the SQL logical server.')
var serverName = 'sqlserver-${uniqueName}'
@description('The name of the SQL Database.')
var sqlDBName = 'SampleDB-${uniqueName}'
@description('The databricks Key Vault name.')
var keyVaultName = 'dbricksKV${uniqueName}'
@description('The adf Key Vault name.')
var adfKeyVaultName = 'adfkeyVault${uniqueName}'
@description('Log Analytic Workspace')
var logAnalyticsWorkspaceName = 'datafactoryworkpace-${uniqueName}'

var httpNYHealhDataLinkedServiceName = 'httpNYHealhData_LS'
var dataLakeStoreLinkedServiceName = 'dataLakeStore_LS'
var sqlServerLinkedServiceName = 'sqlServer_LS'
var databricksLinkedServiceName = 'databricks_LS'
var dataFactoryDataSetInName = 'babyNamesNY_DS'
var csvDataSetName = 'storeLandingZoneBabyNames_DS'
var parquetDataSetName = 'Parquet_DS'
var azureSqlBabyNamesDataSetName = 'AzureSqlBabyNames_DS'
var pipelineName = 'IngestNYBabyNames_PL'
var managedResourceGroupName = '${resourceGroup().name}-${workspaceName}'
var bronzeContainerName = 'bronze'
var silverContainerName = 'silver'
var goldContainerName = 'gold'
var landingContainerName = 'landing'

var contributorRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'b24988ac-6180-42a0-ab88-20f7382dd24c'
) // Role Definition ID for Contributor
var storageBlobDataContributorRole = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
) //Storage Blob Data Contributor

// --- Resources

resource dataFactoryUserIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2021-09-30-preview' = {
  name: 'dataFactoryUserIdentity'
  location: resourceGroup().location
}

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${dataFactoryUserIdentity.id}': {}
    }
  }
}

resource credential 'Microsoft.DataFactory/factories/credentials@2018-06-01' = {
  name: 'credentialDataFactory'
  parent: dataFactory
  properties: {
    type: 'ManagedIdentity'
    typeProperties: {
      resourceId: dataFactoryUserIdentity.id
    }
  }
}

resource httpNYHealhDataLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: httpNYHealhDataLinkedServiceName
  properties: {
    type: 'HttpServer'
    typeProperties: {
      authenticationType: 'Anonymous'
      enableServerCertificateValidation: true
      url: 'https://health.data.ny.gov'
    }
  }
}

resource dataLakeStoreLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: dataLakeStoreLinkedServiceName
  properties: {
    type: 'AzureBlobFS'
    typeProperties: {
      url: 'https://${dataLakeStore.name}.dfs.${environment().suffixes.storage}/'
      credential: {
        referenceName: credential.name
        type: 'CredentialReference'
      }
    }
  }
}

resource databriksLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: databricksLinkedServiceName
  properties: {
    type: 'AzureDatabricks'
    typeProperties: {
      domain: 'https://${databricksWorkspace.properties.workspaceUrl}'
      workspaceResourceId: databricksWorkspace.id
      credential: {
        referenceName: credential.name
        type: 'CredentialReference'
      }
      authentication: 'MSI'
      newClusterNodeType: 'Standard_DS3_v2'
      newClusterNumOfWorker: 1
      newClusterVersion: '14.3.x-scala2.12'
      newClusterInitScripts: []
    }
  }
}

resource sqlServerLinkedService 'Microsoft.DataFactory/factories/linkedservices@2018-06-01' = {
  parent: dataFactory
  name: sqlServerLinkedServiceName
  properties: {
    type: 'AzureSqlDatabase'
    typeProperties: {
      server: sqlServer.properties.fullyQualifiedDomainName
      database: sqlDB.name
      encrypt: 'mandatory'
      trustServerCertificate: false
      hostNameInCertificate: ''
      authenticationType: 'UserAssignedManagedIdentity'
      credential: {
        referenceName: credential.name
        type: 'CredentialReference'
      }
    }
  }
}

resource dataFactoryDataSetIn 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: dataFactoryDataSetInName
  properties: {
    linkedServiceName: {
      referenceName: httpNYHealhDataLinkedService.name
      type: 'LinkedServiceReference'
    }
    type: 'DelimitedText'
    typeProperties: {
      location: {
        type: 'HttpServerLocation'
        relativeUrl: '/resource/jxy9-yhdk.csv?$limit=100000'
      }
      columnDelimiter: ','
      escapeChar: '\\'
      firstRowAsHeader: true
      quoteChar: '\u{0022}'
    }
  }
}

resource csvDataSet 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: csvDataSetName
  properties: {
    linkedServiceName: {
      referenceName: dataLakeStoreLinkedService.name
      type: 'LinkedServiceReference'
    }
    type: 'DelimitedText'
    typeProperties: {
      location: {
        type: 'AzureBlobFSLocation'
        fileName: '@concat(\'nybabynames-\',formatDatetime(utcnow(),\'dd-MM-yyy\'),\'.csv\')'
        fileSystem: landingContainerName
      }
      columnDelimiter: ','
      escapeChar: '\\'
      firstRowAsHeader: true
      quoteChar: '\u{0022}'
    }
  }
}

resource parquetDataSet 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: parquetDataSetName
  properties: {
    linkedServiceName: {
      referenceName: dataLakeStoreLinkedService.name
      type: 'LinkedServiceReference'
    }
    annotations: []
    type: 'Parquet'
    typeProperties: {
      location: {
        type: 'AzureBlobFSLocation'
        fileSystem: 'gold'
      }
      compressionCodec: 'snappy'
    }
    schema: []
  }
}

resource azureSqlBabyNamesDataSet 'Microsoft.DataFactory/factories/datasets@2018-06-01' = {
  parent: dataFactory
  name: azureSqlBabyNamesDataSetName
  properties: {
    linkedServiceName: {
      referenceName: sqlServerLinkedService.name
      type: 'LinkedServiceReference'
    }
    annotations: []
    type: 'AzureSqlTable'
    schema: []
  }
}

resource dataFactoryPipeline 'Microsoft.DataFactory/factories/pipelines@2018-06-01' = {
  parent: dataFactory
  name: pipelineName
  properties: {
    activities: [
      {
        name: 'IngestNYBabyNamesData'
        type: 'Copy'
        typeProperties: {
          source: {
            type: 'DelimitedTextSource'
            storeSettings: {
              type: 'HttpReadSettings'
              requestMethod: 'GET'
            }
            formatSettings: {
              type: 'DelimitedTextReadSettings'
            }
          }
          sink: {
            type: 'DelimitedTextSink'
            storeSettings: {
              type: 'AzureBlobFSWriteSettings'
            }
            formatSettings: {
              type: 'DelimitedTextWriteSettings'
              quoteAllText: true
              fileExtension: '.csv'
            }
          }
          enableStaging: false
        }
        inputs: [
          {
            referenceName: dataFactoryDataSetIn.name
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: csvDataSet.name
            type: 'DatasetReference'
          }
        ]
      }
      {
        name: 'LandingToBronze'
        type: 'DatabricksNotebook'
        dependsOn: [
          {
            activity: 'IngestNYBabyNamesData'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        typeProperties: {
          notebookPath: '/Users/${username}/myLib/landingToBronze'
          baseParameters: {
            _pipeline_run_id: '@pipeline().RunId'
            _filename: '@concat(\'nybabynames-\',formatDatetime(utcnow(),\'dd-MM-yyy\'),\'.csv\')'
            _processing_date: '@formatDatetime(utcnow(),\'dd-MM-yyy HH:mm:ss\')'
          }
        }
        linkedServiceName: {
          referenceName: databriksLinkedService.name
          type: 'LinkedServiceReference'
        }
      }
      {
        name: 'BronzeToSilver'
        type: 'DatabricksNotebook'
        dependsOn: [
          {
            activity: 'LandingToBronze'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        typeProperties: {
          notebookPath: '/Users/${username}/myLib/bronzeToSilver'
          baseParameters: {
            _pipeline_run_id: '@pipeline().RunId'
            _processing_date: '@formatDatetime(utcnow(),\'dd-MM-yyy\')'
          }
        }
        linkedServiceName: {
          referenceName: databriksLinkedService.name
          type: 'LinkedServiceReference'
        }
      }
      {
        name: 'SilverToGold'
        type: 'DatabricksNotebook'
        dependsOn: [
          {
            activity: 'BronzeToSilver'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        typeProperties: {
          notebookPath: '/Users/${username}/myLib/silverToGold'
          baseParameters: {
            _pipeline_run_id: '@pipeline().RunId'
            _processing_date: '@formatDatetime(utcnow(),\'dd-MM-yyy\')'
          }
        }
        linkedServiceName: {
          referenceName: databriksLinkedService.name
          type: 'LinkedServiceReference'
        }
      }
      {
        name: 'CopyDimNames'
        type: 'Copy'
        dependsOn: [
          {
            activity: 'SilverToGold'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        typeProperties: {
          source: {
            type: 'ParquetSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              modifiedDatetimeStart: {
                value: '@adddays(utcnow(),-1)'
                type: 'Expression'
              }
              wildcardFolderPath: 'dim_names'
              wildcardFileName: '*.parquet'
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'ParquetReadSettings'
            }
          }
          sink: {
            type: 'AzureSqlSink'
            sqlWriterStoredProcedureName: '[data].[spOverwriteDimNames]'
            sqlWriterTableType: '[data].[DimNamesType]'
            storedProcedureTableTypeParameterName: 'DimNames'
            disableMetricsCollection: false
          }
          enableStaging: false
          translator: {
            type: 'TabularTranslator'
            mappings: [
              {
                source: {
                  name: 'sid'
                  type: 'Int64'
                  physicalType: 'INT64'
                }
                sink: {
                  name: 'sid'
                  type: 'Int64'
                  physicalType: 'bigint'
                }
              }
              {
                source: {
                  name: 'first_name'
                  type: 'String'
                  physicalType: 'UTF8'
                }
                sink: {
                  name: 'first_name'
                  type: 'String'
                  physicalType: 'nvarchar'
                }
              }
              {
                source: {
                  name: 'sex'
                  type: 'String'
                  physicalType: 'UTF8'
                }
                sink: {
                  name: 'sex'
                  type: 'String'
                  physicalType: 'nvarchar'
                }
              }
            ]
            typeConversion: true
            typeConversionSettings: {
              allowDataTruncation: true
              treatBooleanAsNumber: false
            }
          }
        }
        inputs: [
          {
            referenceName: parquetDataSet.name
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: azureSqlBabyNamesDataSet.name
            type: 'DatasetReference'
          }
        ]
      }
      {
        name: 'CopyDimLocations'
        type: 'Copy'
        dependsOn: [
          {
            activity: 'SilverToGold'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        typeProperties: {
          source: {
            type: 'ParquetSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              modifiedDatetimeStart: {
                value: '@adddays(utcnow(),-1)'
                type: 'Expression'
              }
              wildcardFolderPath: 'dim_locations'
              wildcardFileName: '*.parquet'
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'ParquetReadSettings'
            }
          }
          sink: {
            type: 'AzureSqlSink'
            sqlWriterStoredProcedureName: '[data].[spOverwriteDimLocations]'
            sqlWriterTableType: '[data].[DimLocationsType]'
            storedProcedureTableTypeParameterName: 'DimLocations'
            disableMetricsCollection: false
          }
          enableStaging: false
          translator: {
            type: 'TabularTranslator'
            mappings: [
              {
                source: {
                  name: 'sid'
                  type: 'Int64'
                  physicalType: 'INT64'
                }
                sink: {
                  name: 'sid'
                  type: 'Int64'
                  physicalType: 'bigint'
                }
              }
              {
                source: {
                  name: 'county'
                  type: 'String'
                  physicalType: 'UTF8'
                }
                sink: {
                  name: 'county'
                  type: 'String'
                  physicalType: 'nvarchar'
                }
              }
            ]
            typeConversion: true
            typeConversionSettings: {
              allowDataTruncation: true
              treatBooleanAsNumber: false
            }
          }
        }
        inputs: [
          {
            referenceName: parquetDataSet.name
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: azureSqlBabyNamesDataSet.name
            type: 'DatasetReference'
          }
        ]
      }
      {
        name: 'CopyDimYears'
        type: 'Copy'
        dependsOn: [
          {
            activity: 'SilverToGold'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        typeProperties: {
          source: {
            type: 'ParquetSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              modifiedDatetimeStart: {
                value: '@adddays(utcnow(),-1)'
                type: 'Expression'
              }
              wildcardFolderPath: 'dim_years'
              wildcardFileName: '*.parquet'
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'ParquetReadSettings'
            }
          }
          sink: {
            type: 'AzureSqlSink'
            sqlWriterStoredProcedureName: '[data].[spOverwriteDimYears]'
            sqlWriterTableType: '[data].[DimYearsType]'
            storedProcedureTableTypeParameterName: 'DimYears'
            disableMetricsCollection: false
          }
          enableStaging: false
          translator: {
            type: 'TabularTranslator'
            mappings: [
              {
                source: {
                  name: 'sid'
                  type: 'Int64'
                  physicalType: 'INT64'
                }
                sink: {
                  name: 'sid'
                  type: 'Int64'
                  physicalType: 'bigint'
                }
              }
              {
                source: {
                  name: 'year'
                  type: 'Int32'
                  physicalType: 'INT32'
                }
                sink: {
                  name: 'year'
                  type: 'Int32'
                  physicalType: 'int'
                }
              }
            ]
            typeConversion: true
            typeConversionSettings: {
              allowDataTruncation: true
              treatBooleanAsNumber: false
            }
          }
        }
        inputs: [
          {
            referenceName: parquetDataSet.name
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: azureSqlBabyNamesDataSet.name
            type: 'DatasetReference'
          }
        ]
      }
      {
        name: 'CopyFactBabyNames'
        type: 'Copy'
        dependsOn: [
          {
            activity: 'CopyDimLocations'
            dependencyConditions: [
              'Succeeded'
            ]
          }
          {
            activity: 'CopyDimNames'
            dependencyConditions: [
              'Succeeded'
            ]
          }
          {
            activity: 'CopyDimYears'
            dependencyConditions: [
              'Succeeded'
            ]
          }
        ]
        typeProperties: {
          source: {
            type: 'ParquetSource'
            storeSettings: {
              type: 'AzureBlobFSReadSettings'
              recursive: true
              modifiedDatetimeStart: {
                value: '@adddays(utcnow(),-1)'
                type: 'Expression'
              }
              wildcardFolderPath: 'fact_babynames'
              wildcardFileName: '*.parquet'
              enablePartitionDiscovery: false
            }
            formatSettings: {
              type: 'ParquetReadSettings'
            }
          }
          sink: {
            type: 'AzureSqlSink'
            sqlWriterStoredProcedureName: '[data].[spOverwriteFactBabyNamesType]'
            sqlWriterTableType: '[data].[FactBabyNamesType]'
            storedProcedureTableTypeParameterName: 'FactBabyNames'
            disableMetricsCollection: false
          }
          enableStaging: false
          translator: {
            type: 'TabularTranslator'
            mappings: [
              {
                source: {
                  name: 'sid'
                  type: 'Int64'
                  physicalType: 'INT64'
                }
                sink: {
                  name: 'sid'
                  type: 'Int64'
                  physicalType: 'bigint'
                }
              }
              {
                source: {
                  name: 'nameSid'
                  type: 'Int64'
                  physicalType: 'INT64'
                }
                sink: {
                  name: 'nameSid'
                  type: 'Int64'
                  physicalType: 'bigint'
                }
              }
              {
                source: {
                  name: 'yearSid'
                  type: 'Int64'
                  physicalType: 'INT64'
                }
                sink: {
                  name: 'yearSid'
                  type: 'Int64'
                  physicalType: 'bigint'
                }
              }
              {
                source: {
                  name: 'locationSid'
                  type: 'String'
                  physicalType: 'UTF8'
                }
                sink: {
                  name: 'locationSid'
                  type: 'Int64'
                  physicalType: 'bigint'
                }
              }
              {
                source: {
                  name: 'count'
                  type: 'Int32'
                  physicalType: 'INT32'
                }
                sink: {
                  name: 'count'
                  type: 'Int32'
                  physicalType: 'int'
                }
              }
            ]
            typeConversion: true
            typeConversionSettings: {
              allowDataTruncation: true
              treatBooleanAsNumber: false
            }
          }
        }
        inputs: [
          {
            referenceName: parquetDataSet.name
            type: 'DatasetReference'
          }
        ]
        outputs: [
          {
            referenceName: azureSqlBabyNamesDataSet.name
            type: 'DatasetReference'
          }
        ]
      }
    ]
  }
}

resource managedResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' existing = {
  scope: subscription()
  name: managedResourceGroupName
}

resource databricksWorkspace 'Microsoft.Databricks/workspaces@2018-04-01' = {
  name: workspaceName
  location: location
  sku: {
    name: 'premium'
  }
  properties: {
    managedResourceGroupId: managedResourceGroup.id
    parameters: {
      enableNoPublicIp: {
        value: false
      }
    }
  }
}

resource WorkspaceGeneralLogs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'databricksDiagnostics'
  scope: databricksWorkspace
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    metrics: []
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
  }
}

resource adfToDataBricksContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(databricksWorkspace.id, dataFactoryUserIdentity.id, 'Contributor')
  scope: databricksWorkspace
  properties: {
    roleDefinitionId: contributorRole
    principalId: dataFactoryUserIdentity.properties.principalId
  }
}

resource dataLakeStore 'Microsoft.Storage/storageAccounts@2023-04-01' = {
  name: datalakeStoreName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    publicNetworkAccess: 'Enabled'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    largeFileSharesState: 'Enabled'
    isHnsEnabled: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    accessTier: 'Hot'
  }
}

resource adfToDataLakeStoreContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataLakeStore.id, dataFactoryUserIdentity.id, 'Contributor')
  scope: dataLakeStore
  properties: {
    roleDefinitionId: storageBlobDataContributorRole
    principalId: dataFactoryUserIdentity.properties.principalId
  }
  dependsOn: [
    databricksWorkspace
  ]
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-04-01' = {
  name: 'default'
  parent: dataLakeStore
  properties: {
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
  }
}

resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-04-01' = {
  name: 'default'
  parent: dataLakeStore
  properties: {
    protocolSettings: {
      smb: {}
    }
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource landingContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: landingContainerName
}

resource bronzeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: bronzeContainerName
}

resource silverContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: silverContainerName
}

resource goldContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: goldContainerName
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  properties: {
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    tenantId: tenantId
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

resource accountNameSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'accountName'
  properties: {
    value: dataLakeStore.name
    attributes: {
      exp: secretsExpirationDate
    }
  }
}

resource accountKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'accountKey'
  properties: {
    value: dataLakeStore.listKeys().keys[0].value
    attributes: {
      exp: secretsExpirationDate
    }
  }
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    minimalTlsVersion: '1.2'
    version: '12.0'
    publicNetworkAccess: 'Enabled'
  }
  resource allowAzureServicesRule 'firewallRules' = {
    name: 'AllowAllWindowsAzureIps'
    properties: {
      startIpAddress: '0.0.0.0'
      endIpAddress: '0.0.0.0'
    }
  }
  identity: {
    type: 'SystemAssigned'
  }
  resource activeDirectoryAdmin 'administrators@2023-08-01-preview' = {
    name: 'ActiveDirectory'
    properties: {
      administratorType: 'ActiveDirectory'
      login: username
      sid: userObjectId
      tenantId: userTenantId
    }
  }

  resource sqlADOnlyAuth 'azureADOnlyAuthentications@2023-08-01-preview' = {
    name: 'Default'
    properties: {
      azureADOnlyAuthentication: true
    }
    dependsOn: [
      activeDirectoryAdmin
    ]
  }
}

resource diagnosticSettingsSqlServer 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: sqlServer
  name: '${sqlServer.name}-diag'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
  }
}

resource sqlDB 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDBName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
    capacity: 5
  }
  properties: {
    zoneRedundant: false
    readScale: 'Disabled'
    requestedBackupStorageRedundancy: 'Local'
  }
  dependsOn: [
    sqlServer::sqlADOnlyAuth
    sqlServer::activeDirectoryAdmin
    auditingServerSettings
    sqlVulnerabilityAssessment
  ]
}

resource auditingDbSettings 'Microsoft.Sql/servers/databases/auditingSettings@2023-08-01-preview' = {
  parent: sqlDB
  name: 'default'
  properties: {
    retentionDays: 0
    auditActionsAndGroups: [
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'BATCH_COMPLETED_GROUP'
    ]
    isAzureMonitorTargetEnabled: true
    isManagedIdentityInUse: false
    state: 'Enabled'
    storageAccountSubscriptionId: '00000000-0000-0000-0000-000000000000'
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-06-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018' // Example SKU, adjust as needed
    }
    retentionInDays: 30 // Adjust retention period as needed
  }
}

resource diagnosticSettingsSqlDb 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: sqlDB
  name: '${sqlDB.name}-diag'
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
      }
    ]
  }
}

resource auditingServerSettings 'Microsoft.Sql/servers/auditingSettings@2021-11-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
    auditActionsAndGroups: [
      'SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP'
      'FAILED_DATABASE_AUTHENTICATION_GROUP'
      'BATCH_COMPLETED_GROUP'
    ]
  }
}

resource sqlVulnerabilityAssessment 'Microsoft.Sql/servers/sqlVulnerabilityAssessments@2022-11-01-preview' = {
  name: 'default'
  parent: sqlServer
  properties: {
    state: 'Enabled'
  }
  dependsOn: [
    auditingServerSettings
  ]
}

resource solutions_SQLAuditing_githubmetrics 'Microsoft.OperationsManagement/solutions@2015-11-01-preview' = {
  name: 'SolutionSQLAuditing${logAnalyticsWorkspace.name}'
  location: location
  plan: {
    name: 'SQLAuditing${sqlDB.name}'
    promotionCode: ''
    product: 'SQLAuditing'
    publisher: 'Microsoft'
  }
  properties: {
    workspaceResourceId: logAnalyticsWorkspace.id
    containedResources: [
      '${resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspace.name)}/views/SQLSecurityInsights'
      '${resourceId('Microsoft.OperationalInsights/workspaces', logAnalyticsWorkspace.name)}/views/SQLAccessToSensitiveData'
    ]
    referencedResources: []
  }
}

output name string = dataFactoryPipeline.name
output resourceId string = dataFactoryPipeline.id
output databriksManagedResourceGroup string = managedResourceGroupName
output location string = location
output databricksWorkspaceUrl string = 'https://${databricksWorkspace.properties.workspaceUrl}'
output databricksKeyVaultName string = keyVaultName
output databricksKeyVaultUrl string = kv.properties.vaultUri
output databricksKeyVaultResourceId string = kv.id
output adfKeyVaultName string = adfKeyVaultName
