
function New-AzFunctionApp {
    [OutputType([Microsoft.Azure.PowerShell.Cmdlets.Functions.Models.Api20231201.ISite])]
    [Microsoft.Azure.PowerShell.Cmdlets.Functions.Description('Creates a function app.')]
    [CmdletBinding(SupportsShouldProcess=$true, DefaultParametersetname="Consumption")]
    param(
        [Parameter(ParameterSetName="Consumption", HelpMessage='The Azure subscription ID.')]
        [Parameter(ParameterSetName="ByAppServicePlan")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Runtime.DefaultInfo(Script='(Get-AzContext).Subscription.Id')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${SubscriptionId},
        
        [Parameter(Mandatory=$true, ParameterSetName="Consumption", HelpMessage='The name of the resource group.')]
        [Parameter(Mandatory=$true, ParameterSetName="ByAppServicePlan")]
        [Parameter(Mandatory=$true, ParameterSetName="CustomDockerImage")]
        [Parameter(Mandatory=$true, ParameterSetName="EnvironmentForContainerApp")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${ResourceGroupName},
        
        [Parameter(Mandatory=$true, ParameterSetName="Consumption", HelpMessage='The name of the function app.')]
        [Parameter(Mandatory=$true, ParameterSetName="ByAppServicePlan")]
        [Parameter(Mandatory=$true, ParameterSetName="CustomDockerImage")]
        [Parameter(Mandatory=$true, ParameterSetName="EnvironmentForContainerApp")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${Name},
        
        [Parameter(Mandatory=$true, ParameterSetName="Consumption", HelpMessage='The name of the storage account.')]
        [Parameter(Mandatory=$true, ParameterSetName="ByAppServicePlan")]
        [Parameter(Mandatory=$true, ParameterSetName="CustomDockerImage")]
        [Parameter(Mandatory=$true, ParameterSetName="EnvironmentForContainerApp")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${StorageAccountName},

        [Parameter(ParameterSetName="Consumption", HelpMessage='Name of the existing App Insights project to be added to the function app.')]
        [Parameter(ParameterSetName="ByAppServicePlan")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        [Alias("AppInsightsName")]
        ${ApplicationInsightsName},

        [Parameter(ParameterSetName="Consumption", HelpMessage='Instrumentation key of App Insights to be added.')]
        [Parameter(ParameterSetName="ByAppServicePlan")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        [System.String]
        [Alias("AppInsightsKey")]
        ${ApplicationInsightsKey},

        [Parameter(Mandatory=$true, ParameterSetName="Consumption", HelpMessage='The location for the consumption plan.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${Location},

        [Parameter(Mandatory=$true, ParameterSetName="ByAppServicePlan", HelpMessage='The name of the service plan.')]
        [Parameter(Mandatory=$true, ParameterSetName="CustomDockerImage")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${PlanName},

        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage='The OS to host the function app.')]
        [Parameter(ParameterSetName="Consumption")]
        [ArgumentCompleter([Microsoft.Azure.PowerShell.Cmdlets.Functions.Support.WorkerType])]
        [ValidateSet("Linux", "Windows")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        # OS type (Linux or Windows)
        ${OSType},
        
        [Parameter(Mandatory=$true, ParameterSetName="ByAppServicePlan", HelpMessage='The function runtime.')]
        [Parameter(Mandatory=$true, ParameterSetName="Consumption")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        # Runtime types are defined in HelperFunctions.ps1
        ${Runtime},

        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage='The function runtime.')]
        [Parameter(ParameterSetName="Consumption")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        # RuntimeVersion types are defined in HelperFunctions.ps1
        ${RuntimeVersion},

        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage='The Functions version.')]
        [Parameter(ParameterSetName="Consumption")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        # FunctionsVersion types are defined in HelperFunctions.ps1
        ${FunctionsVersion},

        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage='Disable creating application insights resource during the function app creation. No logs will be available.')]
        [Parameter(ParameterSetName="Consumption")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [System.Management.Automation.SwitchParameter]
        [Alias("DisableAppInsights")]
        ${DisableApplicationInsights},
        
        [Parameter(Mandatory=$true, ParameterSetName="CustomDockerImage", HelpMessage='Container image name, e.g., publisher/image-name:tag.')]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [ValidateNotNullOrEmpty()]
        [System.String]
        [Alias("DockerImageName")]
        ${Image},

        [Parameter(ParameterSetName="CustomDockerImage", HelpMessage='The container registry username and password. Required for private registries.')]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [ValidateNotNullOrEmpty()]
        [PSCredential]
        [Alias("DockerRegistryCredential")]
        ${RegistryCredential},

        [Parameter(HelpMessage='Returns true when the command succeeds.')]
        [System.Management.Automation.SwitchParameter]
        ${PassThru},

        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage='Starts the operation and returns immediately, before the operation is completed. In order to determine if the operation has successfully been completed, use some other mechanism.')]
        [Parameter(ParameterSetName="Consumption")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Runtime')]
        [System.Management.Automation.SwitchParameter]
        ${NoWait},
        
        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage='Runs the cmdlet as a background job.')]
        [Parameter(ParameterSetName="Consumption")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Runtime')]
        [System.Management.Automation.SwitchParameter]
        ${AsJob},

        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage='Resource tags.')]
        [Parameter(ParameterSetName="Consumption")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Body')]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Runtime.Info(PossibleTypes=([Microsoft.Azure.PowerShell.Cmdlets.Functions.Models.Api20231201.IResourceTags]))]
        [System.Collections.Hashtable]
        [ValidateNotNull()]
        ${Tag},

        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage='Function app settings.')]
        [Parameter(ParameterSetName="Consumption")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [ValidateNotNullOrEmpty()]
        [Hashtable]
        ${AppSetting},

        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage="Specifies the type of identity used for the function app.
            The acceptable values for this parameter are:
            - SystemAssigned
            - UserAssigned
            ")]
        [Parameter(ParameterSetName="Consumption")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [ArgumentCompleter([Microsoft.Azure.PowerShell.Cmdlets.Functions.Support.FunctionAppManagedServiceIdentityCreateType])]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Body')]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Support.ManagedServiceIdentityType]
        ${IdentityType},

        [Parameter(ParameterSetName="ByAppServicePlan", HelpMessage="Specifies the list of user identities associated with the function app.
            The user identity references will be ARM resource ids in the form:
            '/subscriptions/{subscriptionId}/resourceGroups/{resourceGroupName}/providers/Microsoft.ManagedIdentity/identities/{identityName}'")]
        [Parameter(ParameterSetName="Consumption")]
        [Parameter(ParameterSetName="CustomDockerImage")]
        [Parameter(ParameterSetName="EnvironmentForContainerApp")]
        [ValidateNotNull()]
        [System.String[]]
        ${IdentityID},

        [Parameter(Mandatory=$true, ParameterSetName="EnvironmentForContainerApp", HelpMessage='Name of the container app environment.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${Environment},

        [Parameter(Mandatory=$false, ParameterSetName="EnvironmentForContainerApp", HelpMessage='The workload profile name to run the container app on.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${WorkloadProfileName},

        [Parameter(Mandatory=$false, ParameterSetName="EnvironmentForContainerApp", HelpMessage='The CPU in cores of the container app. e.g., 0.75.')]
        [ValidateNotNullOrEmpty()]
        [Double]
        ${ResourceCpu},

        [Parameter(Mandatory=$false, ParameterSetName="EnvironmentForContainerApp", HelpMessage='The memory size of the container app. e.g., 1.0Gi.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${ResourceMemory},

        [Parameter(Mandatory=$false, ParameterSetName="EnvironmentForContainerApp", HelpMessage='The maximum number of replicas when creating a function app on container app.')]
        [ValidateScript({$_ -gt 0})]
        [Int]
        ${ScaleMaxReplica},

        [Parameter(Mandatory=$false, ParameterSetName="EnvironmentForContainerApp", HelpMessage='The minimum number of replicas when create function app on container app.')]
        [ValidateScript({$_ -gt 0})]
        [Int]
        ${ScaleMinReplica},

        [Parameter(Mandatory=$false, ParameterSetName="EnvironmentForContainerApp", HelpMessage='The container registry server hostname, e.g. myregistry.azurecr.io.')]
        [ValidateNotNullOrEmpty()]
        [System.String]
        ${RegistryServer},
        
        [Alias('AzureRMContext', 'AzureCredential')]
        [ValidateNotNull()]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Azure')]
        [System.Management.Automation.PSObject]
        ${DefaultProfile},

        [Parameter(DontShow)]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Runtime')]
        [System.Management.Automation.SwitchParameter]
        # Wait for .NET debugger to attach
        ${Break},

        [Parameter(DontShow)]
        [ValidateNotNull()]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Runtime')]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Runtime.SendAsyncStep[]]
        # SendAsync Pipeline Steps to be appended to the front of the pipeline
        ${HttpPipelineAppend},

        [Parameter(DontShow)]
        [ValidateNotNull()]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Runtime')]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Runtime.SendAsyncStep[]]
        # SendAsync Pipeline Steps to be prepended to the front of the pipeline
        ${HttpPipelinePrepend},

        [Parameter(DontShow)]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Runtime')]
        [System.Uri]
        # The URI for the proxy server to use
        ${Proxy},

        [Parameter(DontShow)]
        [ValidateNotNull()]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Runtime')]
        [System.Management.Automation.PSCredential]
        # Credentials for a proxy server to use for the remote call
        ${ProxyCredential},

        [Parameter(DontShow)]
        [Microsoft.Azure.PowerShell.Cmdlets.Functions.Category('Runtime')]
        [System.Management.Automation.SwitchParameter]
        # Use the default credentials for the proxy
        ${ProxyUseDefaultCredentials}
    )

    process {

        RegisterFunctionsTabCompleters

        # Remove bound parameters from the dictionary that cannot be process by the intenal cmdlets.
        $paramsToRemove = @(
            "StorageAccountName",
            "ApplicationInsightsName",
            "ApplicationInsightsKey",
            "Location",
            "PlanName",
            "OSType",
            "Runtime",
            "DisableApplicationInsights",
            "Image",
            "RegistryCredential",
            "FunctionsVersion",
            "RuntimeVersion",
            "AppSetting",
            "IdentityType",
            "IdentityID",
            "Tag",
            "Environment",
            "RegistryServer",
            "WorkloadProfileName",
            "ResourceCpu",
            "ResourceMemory",
            "ScaleMaxReplica",
            "ScaleMinReplica"
        )
        foreach ($paramName in $paramsToRemove)
        {
            if ($PSBoundParameters.ContainsKey($paramName))
            {
                $PSBoundParameters.Remove($paramName)  | Out-Null
            }
        }

        $functionAppIsCustomDockerImage = $PsCmdlet.ParameterSetName -eq "CustomDockerImage"
        $environmentForContainerApp = $PsCmdlet.ParameterSetName -eq "EnvironmentForContainerApp"

        $appSettings = New-Object -TypeName System.Collections.Generic.List[System.Object]
        $siteConfig = New-Object -TypeName Microsoft.Azure.PowerShell.Cmdlets.Functions.Models.Api20231201.SiteConfig
        $functionAppDef = New-Object -TypeName Microsoft.Azure.PowerShell.Cmdlets.Functions.Models.Api20231201.Site

        $params = GetParameterKeyValues -PSBoundParametersDictionary $PSBoundParameters `
                                        -ParameterList @("SubscriptionId", "HttpPipelineAppend", "HttpPipelinePrepend")

        $runtimeJsonDefinition = $null
        ValidateFunctionName -Name $Name @params

        if (-not ($functionAppIsCustomDockerImage -or $environmentForContainerApp))
        {
            if (-not $FunctionsVersion)
            {
                $FunctionsVersion = $DefaultFunctionsVersion
                Write-Warning "FunctionsVersion not specified. Setting default value to '$FunctionsVersion'. $SetDefaultValueParameterWarningMessage"
            }

            ValidateFunctionsVersion -FunctionsVersion $FunctionsVersion

            if (-not $OSType)
            {
                $OSType = GetDefaultOSType -Runtime $Runtime
                Write-Warning "OSType not specified. Setting default value to '$OSType'. $SetDefaultValueParameterWarningMessage"
            }

            $runtimeJsonDefinition = GetStackDefinitionForRuntime -FunctionsVersion $FunctionsVersion -Runtime $Runtime -RuntimeVersion $RuntimeVersion -OSType $OSType

            if (-not $runtimeJsonDefinition)
            {
                $errorId = "FailedToGetRuntimeDefinition"
                $message += "Failed to get runtime definition for '$Runtime' version '$RuntimeVersion' in Functions version '$FunctionsVersion' on '$OSType'."
                $exception = [System.InvalidOperationException]::New($message)
                ThrowTerminatingError -ErrorId $errorId `
                                      -ErrorMessage $message `
                                      -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                                      -Exception $exception

            }

            # Add app settings
            if ($runtimeJsonDefinition.AppSettingsDictionary.Count -gt 0)
            {
                foreach ($keyName in $runtimeJsonDefinition.AppSettingsDictionary.Keys)
                {
                    $value = $runtimeJsonDefinition.AppSettingsDictionary[$keyName]
                    $appSettings.Add((NewAppSetting -Name $keyName -Value $value))
                }
            }

            # Add site config properties
            if ($runtimeJsonDefinition.SiteConfigPropertiesDictionary.Count -gt 0)
            {
                foreach ($PropertyName in $runtimeJsonDefinition.SiteConfigPropertiesDictionary.Keys)
                {
                    $value = $runtimeJsonDefinition.SiteConfigPropertiesDictionary[$PropertyName]
                    $siteConfig.$PropertyName = $value
                }
            }            
        }

        $servicePlan = $null
        $consumptionPlan = $PsCmdlet.ParameterSetName -eq "Consumption"
        $OSIsLinux = $OSType -eq "Linux"
        $dockerRegistryServerUrl = $null
        
        if ($consumptionPlan)
        {
            ValidateConsumptionPlanLocation -Location $Location -OSIsLinux:$OSIsLinux @params
            $functionAppDef.Location = $Location
        }
        elseif ($environmentForContainerApp)
        {
            $OSIsLinux = $true

            if (-not $Image)
            {
                Write-Warning "Image not specified. Setting default value to '$DefaultCentauriImage'."
                $Image = $DefaultCentauriImage
            }
            if ($RegistryServer)
            {
                $dockerRegistryServerUrl = $RegistryServer
            }

            if ($Environment -and $RegistryCredential)
            {
                # Error out if the user has specified both Environment and RegistryCredential and not provided RegistryServer.
                if (-not $RegistryServer)
                {
                    $errorMessage = "RegistryServer is required when Environment and RegistryCredential is specified."
                    $exception = [System.InvalidOperationException]::New($errorMessage)
                    ThrowTerminatingError -ErrorId "RegistryServerRequired" `
                                          -ErrorMessage $errorMessage `
                                          -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                                          -Exception $exception
                }
            }
        }
        elseif ($PlanName)
        {
            # Host function app in Elastic Premium or app service plan
            $servicePlan = GetServicePlan $PlanName @params

            if ($null -ne $servicePlan.Location)
            {
                $Location = $servicePlan.Location
            }

            if ($null -ne $servicePlan.Reserved)
            {
                $OSIsLinux = $servicePlan.Reserved
            }

            $functionAppDef.ServerFarmId = $servicePlan.Id
            $functionAppDef.Location = $Location
        }

        if ($OSIsLinux)
        {
            # These are the scenarios we currently support when creating a Docker container:
            # 1) In Consumption, we only support images created by Functions with a predefine runtime name and version, e.g., Python 3.7
            # 2) For App Service and Premium plans, a customer can specify a customer container image

            # Linux function app
            $functionAppDef.Kind = 'functionapp,linux'
            $functionAppDef.Reserved = $true

            # Bring your own container is only supported on App Service, Premium plans and Container App
            if ($Image)
            {
                $functionAppDef.Kind = 'functionapp,linux,container'

                $appSettings.Add((NewAppSetting -Name 'DOCKER_CUSTOM_IMAGE_NAME' -Value $Image.Trim().ToLower()))
                $appSettings.Add((NewAppSetting -Name 'FUNCTION_APP_EDIT_MODE' -Value 'readOnly'))
                $appSettings.Add((NewAppSetting -Name 'WEBSITES_ENABLE_APP_SERVICE_STORAGE' -Value 'false'))

                $siteConfig.LinuxFxVersion = FormatFxVersion -Image $Image

                # Parse the docker registry url only for the custom image parameter set (otherwise it will be a breaking change for existing customers).
                # For the container app environment, the registry url must me explicitly provided.
                if (-not $dockerRegistryServerUrl -and -not $environmentForContainerApp)
                {
                    $dockerRegistryServerUrl = ParseDockerImage -DockerImageName $Image
                }

                if ($dockerRegistryServerUrl)
                {
                    $appSettings.Add((NewAppSetting -Name 'DOCKER_REGISTRY_SERVER_URL' -Value $dockerRegistryServerUrl))

                    if ($RegistryCredential)
                    {
                        $appSettings.Add((NewAppSetting -Name 'DOCKER_REGISTRY_SERVER_USERNAME' -Value $RegistryCredential.GetNetworkCredential().UserName))
                        $appSettings.Add((NewAppSetting -Name 'DOCKER_REGISTRY_SERVER_PASSWORD' -Value $RegistryCredential.GetNetworkCredential().Password))
                    }
                }
            }
            else
            {
                $appSettings.Add((NewAppSetting -Name 'WEBSITES_ENABLE_APP_SERVICE_STORAGE' -Value 'true'))
            }
        }
        else 
        {
            # Windows function app
            $functionAppDef.Kind = 'functionapp'
        }

        if ($environmentForContainerApp)
        {
            $functionAppDef.Kind = 'functionapp,linux,container,azurecontainerapps'
            $functionAppDef.Reserved = $null
            $functionAppDef.HttpsOnly = $null
            $functionAppDef.ScmSiteAlsoStopped = $null
            $functionAppDef.HttpsOnly = $null

            ValidateCpuAndMemory -ResourceCpu $ResourceCpu -ResourceMemory $ResourceMemory
            if ($ResourceCpu -and $ResourceMemory)
            {
                $functionAppDef.ResourceConfigCpu = $ResourceCpu
                $functionAppDef.ResourceConfigMemory = $ResourceMemory
            }

            if ($WorkloadProfileName)
            {
                $functionAppDef.WorkloadProfileName = $WorkloadProfileName
            }

            $siteConfig.netFrameworkVersion = $null
            $siteConfig.JavaVersion = $null
            $siteConfig.Use32BitWorkerProcess = $null
            $siteConfig.PowerShellVersion = $null
            $siteConfig.Http20Enabled = $null
            $siteConfig.LocalMySqlEnabled = $null

            if ($ScaleMinReplica)
            {
                $siteConfig.MinimumElasticInstanceCount = $ScaleMinReplica
            }

            if ($ScaleMaxReplica)
            {
                $siteConfig.FunctionAppScaleLimit = $ScaleMaxReplica
            }
            
            $managedEnvironment = GetManagedEnvironment -Environment $Environment -ResourceGroupName $ResourceGroupName
            $functionAppDef.Location = $managedEnvironment.Location
            $functionAppDef.ManagedEnvironmentId = $managedEnvironment.Id
        }

        # Validate storage account and get connection string
        $connectionString = GetConnectionString -StorageAccountName $StorageAccountName @params
        $appSettings.Add((NewAppSetting -Name 'AzureWebJobsStorage' -Value $connectionString))
        $appSettings.Add((NewAppSetting -Name 'AzureWebJobsDashboard' -Value $connectionString))

        if (-not ($functionAppIsCustomDockerImage -or $environmentForContainerApp))
        {
            $appSettings.Add((NewAppSetting -Name 'FUNCTIONS_EXTENSION_VERSION' -Value "~$FunctionsVersion"))
        }

        # If plan is not consumption, elastic premium or a container app environment, set always on
        $planIsElasticPremium = $servicePlan.SkuTier -eq 'ElasticPremium'
        if ((-not $consumptionPlan) -and (-not $planIsElasticPremium) -and (-not $Environment))
        {
            $siteConfig.AlwaysOn = $true
        }

        # If plan is Elastic Premium or Consumption (Windows or Linux), we need these app settings
        if ($planIsElasticPremium -or $consumptionPlan)
        {
            $appSettings.Add((NewAppSetting -Name 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING' -Value $connectionString))

            $shareName = GetShareName -FunctionAppName $Name
            $appSettings.Add((NewAppSetting -Name 'WEBSITE_CONTENTSHARE' -Value $shareName))
        }

        if (-not $DisableApplicationInsights)
        {
            if ($ApplicationInsightsKey)
            {
                $appSettings.Add((NewAppSetting -Name 'APPINSIGHTS_INSTRUMENTATIONKEY' -Value $ApplicationInsightsKey))
            }
            elseif ($ApplicationInsightsName)
            {
                $appInsightsProject = GetApplicationInsightsProject -Name $ApplicationInsightsName @params
                if (-not $appInsightsProject)
                {
                    $errorMessage = "Failed to get application insights key for project name '$ApplicationInsightsName'. Please make sure the project exist."
                    $exception = [System.InvalidOperationException]::New($errorMessage)
                    ThrowTerminatingError -ErrorId "ApplicationInsightsProjectNotFound" `
                                        -ErrorMessage $errorMessage `
                                        -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                                        -Exception $exception
                }

                $appSettings.Add((NewAppSetting -Name 'APPINSIGHTS_INSTRUMENTATIONKEY' -Value $appInsightsProject.InstrumentationKey))
            }
            else
            {
                $newAppInsightsProject = CreateApplicationInsightsProject -ResourceGroupName $resourceGroupName `
                                                                          -ResourceName $Name `
                                                                          -Location $functionAppDef.Location `
                                                                          @params
                if ($newAppInsightsProject)
                {
                    $appSettings.Add((NewAppSetting -Name 'APPINSIGHTS_INSTRUMENTATIONKEY' -Value $newAppInsightsProject.InstrumentationKey))
                }
                else
                {
                    $warningMessage = "Unable to create the Application Insights for the function app. Creation of Application Insights will help you monitor and diagnose your function apps in the Azure Portal. `r`n"
                    $warningMessage += "Use the 'New-AzApplicationInsights' cmdlet or the Azure Portal to create a new Application Insights project. After that, use the 'Update-AzFunctionApp' cmdlet to update Application Insights for your function app."
                    Write-Warning $warningMessage
                }
            }
        }

        if ($Tag.Count -gt 0)
        {
            $resourceTag = NewResourceTag -Tag $Tag
            $functionAppDef.Tag = $resourceTag
        }

        # Add user app settings
        if ($appSetting.Count -gt 0)
        {
            foreach ($keyName in $appSetting.Keys)
            {
                $appSettings.Add((NewAppSetting -Name $keyName -Value $appSetting[$keyName]))
            }
        }

        # Set function app managed identity
        if ($IdentityType)
        {
            $functionAppDef.IdentityType = $IdentityType

            if ($IdentityType -eq "UserAssigned")
            {
                # Set UserAssigned managed identiy
                if (-not $IdentityID)
                {
                    $errorMessage = "IdentityID is required for UserAssigned identity"
                    $exception = [System.InvalidOperationException]::New($errorMessage)
                    ThrowTerminatingError -ErrorId "IdentityIDIsRequiredForUserAssignedIdentity" `
                                            -ErrorMessage $errorMessage `
                                            -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                                            -Exception $exception

                }

                $identityUserAssignedIdentity = NewIdentityUserAssignedIdentity -IdentityID $IdentityID
                $functionAppDef.IdentityUserAssignedIdentity = $identityUserAssignedIdentity
            }
        }

        # Set app settings and site configuration
        $siteConfig.AppSetting = $appSettings
        $functionAppDef.Config = $siteConfig
        $PSBoundParameters.Add("SiteEnvelope", $functionAppDef)  | Out-Null

        if ($PsCmdlet.ShouldProcess($Name, "Creating function app"))
        {
            # Save the ErrorActionPreference
            $currentErrorActionPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Stop'

            $exceptionThrown = $false

            try
            {
                Az.Functions.internal\New-AzFunctionApp @PSBoundParameters
            }
            catch
            {
                $exceptionThrown = $true

                $errorMessage = GetErrorMessage -Response $_

                if ($errorMessage)
                {
                    $exception = [System.InvalidOperationException]::New($errorMessage)
                    ThrowTerminatingError -ErrorId "FailedToCreateFunctionApp" `
                                            -ErrorMessage $errorMessage `
                                            -ErrorCategory ([System.Management.Automation.ErrorCategory]::InvalidOperation) `
                                            -Exception $exception
                }

                throw $_
            }
            finally
            {
                # Reset the ErrorActionPreference
                $ErrorActionPreference = $currentErrorActionPreference
            }

            if (-not $exceptionThrown)
            {
                if ($consumptionPlan -and $OSIsLinux)
                {
                    $message = "Your Linux function app '$Name', that uses a consumption plan has been successfully created but is not active until content is published using Azure Portal or the Functions Core Tools."
                    Write-Verbose $message -Verbose
                }
            }
        }
    }
}

# SIG # Begin signature block
# MIIoRgYJKoZIhvcNAQcCoIIoNzCCKDMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAysI9JXbowLlbJ
# 4pzs4wTMJ4SfGJVLBz0GjLO89pKXU6CCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
# Bv9XKydyAAAAAAQEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjQwOTEyMjAxMTE0WhcNMjUwOTExMjAxMTE0WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC0KDfaY50MDqsEGdlIzDHBd6CqIMRQWW9Af1LHDDTuFjfDsvna0nEuDSYJmNyz
# NB10jpbg0lhvkT1AzfX2TLITSXwS8D+mBzGCWMM/wTpciWBV/pbjSazbzoKvRrNo
# DV/u9omOM2Eawyo5JJJdNkM2d8qzkQ0bRuRd4HarmGunSouyb9NY7egWN5E5lUc3
# a2AROzAdHdYpObpCOdeAY2P5XqtJkk79aROpzw16wCjdSn8qMzCBzR7rvH2WVkvF
# HLIxZQET1yhPb6lRmpgBQNnzidHV2Ocxjc8wNiIDzgbDkmlx54QPfw7RwQi8p1fy
# 4byhBrTjv568x8NGv3gwb0RbAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQU8huhNbETDU+ZWllL4DNMPCijEU4w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMjkyMzAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIjmD9IpQVvfB1QehvpC
# Ge7QeTQkKQ7j3bmDMjwSqFL4ri6ae9IFTdpywn5smmtSIyKYDn3/nHtaEn0X1NBj
# L5oP0BjAy1sqxD+uy35B+V8wv5GrxhMDJP8l2QjLtH/UglSTIhLqyt8bUAqVfyfp
# h4COMRvwwjTvChtCnUXXACuCXYHWalOoc0OU2oGN+mPJIJJxaNQc1sjBsMbGIWv3
# cmgSHkCEmrMv7yaidpePt6V+yPMik+eXw3IfZ5eNOiNgL1rZzgSJfTnvUqiaEQ0X
# dG1HbkDv9fv6CTq6m4Ty3IzLiwGSXYxRIXTxT4TYs5VxHy2uFjFXWVSL0J2ARTYL
# E4Oyl1wXDF1PX4bxg1yDMfKPHcE1Ijic5lx1KdK1SkaEJdto4hd++05J9Bf9TAmi
# u6EK6C9Oe5vRadroJCK26uCUI4zIjL/qG7mswW+qT0CW0gnR9JHkXCWNbo8ccMk1
# sJatmRoSAifbgzaYbUz8+lv+IXy5GFuAmLnNbGjacB3IMGpa+lbFgih57/fIhamq
# 5VhxgaEmn/UjWyr+cPiAFWuTVIpfsOjbEAww75wURNM1Imp9NJKye1O24EspEHmb
# DmqCUcq7NqkOKIG4PVm3hDDED/WQpzJDkvu4FrIbvyTGVU01vKsg4UfcdiZ0fQ+/
# V0hf8yrtq9CkB8iIuk5bBxuPMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGiYwghoiAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEO
# MAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIM3LlgImWoUKlOZPNXb3+j+w
# ql9ZlcuZjZ1tj4rOW7fVMEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8A
# cwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEB
# BQAEggEAYsAotW1TTHHmupCv6ZeqkXoKWiiBXrVNYmyzIXoz40+7TTMzFv8riOsC
# pyRVpfFEJPVHbbzJjuRUArHidxuFZ2rNJd5HbqXBky6i6eJhslyEKE2PINY3+w7F
# vD88OR6iU1qhT7xSRIa8VH5FJsVye97WLl5hV9fEpYadOXxlKgR8LrtDOUNdWI25
# PKwlMZXPIEtwJ2ve0R5iSDN7F1E5dNZrSlDic4LISqmquapi4obmmfC2zZy3oKJJ
# LiQLrEHgryx1rLxEVL/XgFf70Y3oEh4O/aIPx9BB8J4Gh36yP524Q8bCLUJIQ+zv
# 7ZhU7WGYMr0Tbni70IXEjKeyBB5x+6GCF7AwghesBgorBgEEAYI3AwMBMYIXnDCC
# F5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsq
# hkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFl
# AwQCAQUABCDEyFB7voa76TfpauhO6pUTtZdyO3Qr2CAin0D0IM8+UwIGZ2K77bwh
# GBMyMDI1MDEwOTA2Mzc0OC4zNzJaMASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJl
# bGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVT
# TjozMjFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# U2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB+KOhJgwMQEj+AAEAAAH4MA0G
# CSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI0
# MDcyNTE4MzEwOFoXDTI1MTAyMjE4MzEwOFowgdMxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9w
# ZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjMyMUEt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAxR23pXYnD2BuODdeXs2C
# u/T5kKI+bAw8cbtN50Cm/FArjXyL4RTqMe6laQ/CqeMTxgckvZr1JrW0Mi4F15rx
# /VveGhKBmob45DmOcV5xyx7h9Tk59NAl5PNMAWKAIWf270SWAAWxQbpVIhhPWCnV
# V3otVvahEad8pMmoSXrT5Z7Nk1RnB70A2bq9Hk8wIeC3vBuxEX2E8X50IgAHsyaR
# 9roFq3ErzUEHlS8YnSq33ui5uBcrFOcFOCZILuVFVTgEqSrX4UiX0etqi7jUtKyp
# gIflaZcV5cI5XI/eCxY8wDNmBprhYMNlYxdmQ9aLRDcTKWtddWpnJtyl5e3gHuYo
# j8xuDQ0XZNy7ESRwJIK03+rTZqfaYyM4XSK1s0aa+mO69vo/NmJ4R/f1+KucBPJ4
# yUdbqJWM3xMvBwLYycvigI/WK4kgPog0UBNczaQwDVXpcU+TMcOvWP8HBWmWJQIm
# TZInAFivXqUaBbo3wAfPNbsQpvNNGu/12pg0F8O/CdRfgPHfOhIWQ0D8ALCY+Lsi
# wbzcejbrVl4N9fn2wOg2sDa8RfNoD614I0pFjy/lq1NsBo9V4GZBikzX7ZjWCRgd
# 1FCBXGpfpDikHjQ05YOkAakdWDT2bGSaUZJGVYtepIpPTAs1gd/vUogcdiL51o7s
# huHIlB6QSUiQ24XYhRbbQCECAwEAAaOCAUkwggFFMB0GA1UdDgQWBBS9zsZzz57Q
# lT5nrt/oitLv1OQ7tjAfBgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBf
# BgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3Bz
# L2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmww
# bAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0El
# MjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUF
# BwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAYfk8GzzpEVnG
# l7y6oXoytCb42Hx6TOA0+dkaBI36ftDE9tLubUa/xMbHB5rcNiRhFHZ93RefdPpc
# 4+FF0DAl5lP8xKAO+293RWPKDFOFIxgtZY08t8D9cSQpgGUzyw3lETZebNLEA17A
# /CTpA2F9uh8j84KygeEbj+bidWDiEfayoH2A5/5ywJJxIuLzFVHacvWxSCKoF9hl
# SrZSG5fXWS3namf4tt690UT6AGyWLFWe895coFPxm/m0UIMjjp9VRFH7nb3Ng2Q4
# gPS9E5ZTMZ6nAlmUicDj0NXAs2wQuQrnYnbRAJ/DQW35qLo7Daw9AsItqjFhbMcG
# 68gDc4j74L2KYe/2goBHLwzSn5UDftS1HZI0ZRsqmNHI0TZvvUWX9ajm6SfLBTEt
# oTo6gLOX0UD/9rrhGjdkiCw4SwU5osClgqgiNMK5ndk2gxFlDXHCyLp5qB6BoPpc
# 82RhO0yCzoP9gv7zv2EocAWEsqE5+0Wmu5uarmfvcziLfU1SY240OZW8ld4sS8fn
# ybn/jDMmFAhazV1zH0QERWEsfLSpwkOXaImWNFJ5lmcnf1VTm6cmfasScYtElpjq
# Z9GooCmk1XFApORPs/PO43IcFmPRwagt00iQSw+rBeIH00KQq+FJT/62SB70g9g/
# R8TS6k6b/wt2UWhqrW+Q8lw6Xzgex/YwggdxMIIFWaADAgECAhMzAAAAFcXna54C
# m0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UE
# CBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9z
# b2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZp
# Y2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMy
# MjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNV
# BAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51
# yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY
# 6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9
# cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN
# 7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDua
# Rr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74
# kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2
# K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5
# TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZk
# i1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9Q
# BXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3Pmri
# Lq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUC
# BBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJl
# pxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIB
# FjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9y
# eS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUA
# YgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# 1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIw
# MTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/yp
# b+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulm
# ZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM
# 9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECW
# OKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4
# FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3Uw
# xTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPX
# fx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVX
# VAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGC
# onsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU
# 5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEG
# ahC0HVUzWLOhcGbyoYIDWTCCAkECAQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJl
# bGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVT
# TjozMjFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAg
# U2VydmljZaIjCgEBMAcGBSsOAwIaAxUAtkQt/ebWSQ5DnG+aKRzPELCFE9GggYMw
# gYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsF
# AAIFAOspkbIwIhgPMjAyNTAxMDkwMDA3MTRaGA8yMDI1MDExMDAwMDcxNFowdzA9
# BgorBgEEAYRZCgQBMS8wLTAKAgUA6ymRsgIBADAKAgEAAgI4NAIB/zAHAgEAAgIS
# NjAKAgUA6yrjMgIBADA2BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAow
# CAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQCjGHrWu30V
# S+qaHfvanyYyDmqqh6hS8P5IdktEfCKInL73NSc2gsWB/fPKwfPjKEofdwRRyvdX
# 8NDC4nzL7+kKr7S+oFtAlZl5e5iueeJLpVD5/73C43eTcpuRUC7o1Y+JHJ634L0I
# wwbPclEapYNWMzeTQolR4qe/RO6Qsa+PQ+RV/Om9lWMap4f16DgeyL80ClPEXUhd
# YUHZD5jVu/HI7zt33nJ6kphWurwD4hzxEl8ndMNtBAQDIVm5n1AoocnUOOaAWTVe
# tkFNK3JrW2tk3V5PK+ZSK8N1gW0PmjurnJP5u87pCYMSu+JNKZxQlEyWiiVscroQ
# vtM0sN1P4QOeMYIEDTCCBAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENB
# IDIwMTACEzMAAAH4o6EmDAxASP4AAQAAAfgwDQYJYIZIAWUDBAIBBQCgggFKMBoG
# CSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgJgzlmASw
# JUJmfC/fymrL+4X0pT98Y/ItWjvTpyPekwkwgfoGCyqGSIb3DQEJEAIvMYHqMIHn
# MIHkMIG9BCDvzDPyXw1UkAUFYt8bR4UdjM90Qv5xnVaiKD3I0Zz3WjCBmDCBgKR+
# MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdS
# ZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMT
# HU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAB+KOhJgwMQEj+AAEA
# AAH4MCIEIIDqYkMBBSXNi5DSosKMktNwXGOG4bQj+zBd999wCCwEMA0GCSqGSIb3
# DQEBCwUABIICADt9d4YQCqlauBTexYbeLvcpq4nsYUhX+PF2Z/fmYQ3tZo9l9oO9
# FsO5PFwLqNQlhuMSKfr9lo7ig1/QwX6yqIrwocvmWB6FPwePV5BCy0suJCeSCuIu
# t5S9Ehz1KII5s3Tz+ZmmrFx3YU0AZgfmn0+z6/mbOFdFO1LLnA0gd+IBudqAbBpo
# mnyIJncxHtLX/iS71Asex4ySXx8XjadjcD4TTYR5oBda1NAmi+Ic/krGxQE8OrhH
# sBRIEztqDBwK8OSKcBsN2ftmUst/FMbzQECvnxFUqYntlQAmFuayhnexiwvtsrGe
# aQogpmoEELtvbvq1kdAcqhquhYqX0SCqJrvKdI7hNuLXoBQftFtzcpUkQbhg+Tdv
# 94ylW7hGn+eq8DXHRjXAL1GU7Kr/jC4TA814HJ354dkXLksyXrBplf4OOwqQQltd
# Ctv8lSgv06F6oLRZIsXGRyBssuuaV5CNFcZOxch//+eTirMo469A+/XWnaUCIstL
# kq78hdzohvt1sOaA82JDJGnJ0nwA4vBPh9y/akdyX1hvzn6vq2cKFL5U7Qm7TKCp
# yR8djwOdOQszabhRJV1VAkRpFddrFQ1k5LEDkC0V9YcGooH9uWvSpnKAj2vo6lMZ
# 6c1Knk4GVW614qfJxWWumdCq1Npl9H1k+6TzV7+PmQ3979mQpRiLPr2a
# SIG # End signature block
