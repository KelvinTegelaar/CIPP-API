using namespace System.Net

function Invoke-ExecOnboardTenant {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Request, $TriggerMetadata)

    $APIName = 'ExecOnboardTenant'
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Id = $Request.Body.id
    if ($Id) {
        try {
            $OnboardTable = Get-CIPPTable -TableName 'TenantOnboarding'
            $TenantOnboarding = Get-CIPPAzDataTableEntity @OnboardTable -Filter "RowKey eq '$Id'"

            if (!$TenantOnboarding -or [bool]$Request.Query.Retry) {
                $OnboardingSteps = [PSCustomObject]@{
                    'Step1' = @{
                        'Status'  = 'pending'
                        'Title'   = 'Step 1: GDAP Invite'
                        'Message' = 'Waiting for onboarding job to start'
                    }
                    'Step2' = @{
                        'Status'  = 'pending'
                        'Title'   = 'Step 2: GDAP Role Test'
                        'Message' = 'Waiting for Step 1'
                    }
                    'Step3' = @{
                        'Status'  = 'pending'
                        'Title'   = 'Step 3: GDAP Group Mapping'
                        'Message' = 'Waiting for Step 2'
                    }
                    'Step4' = @{
                        'Status'  = 'pending'
                        'Title'   = 'Step 4: CPV Refresh'
                        'Message' = 'Waiting for Step 3'
                    }
                    'Step5' = @{
                        'Status'  = 'pending'
                        'Title'   = 'Step 5: Graph API Test'
                        'Message' = 'Waiting for Step 4'
                    }
                }
                $TenantOnboarding = [PSCustomObject]@{
                    PartitionKey    = 'Onboarding'
                    RowKey          = [string]$Id
                    CustomerId      = ''
                    Status          = 'queued'
                    OnboardingSteps = [string](ConvertTo-Json -InputObject $OnboardingSteps -Compress)
                    Relationship    = ''
                    Logs            = ''
                    Exception       = ''
                }
                Add-CIPPAzDataTableEntity @OnboardTable -Entity $TenantOnboarding -Force -ErrorAction Stop

                $Item = [pscustomobject]@{
                    FunctionName     = 'ExecOnboardTenantQueue'
                    id               = $Id
                    Roles            = $Request.Body.gdapRoles
                    AddMissingGroups = $Request.Body.addMissingGroups
                    AutoMapRoles     = $Request.Body.autoMapRoles
                }

                $InputObject = @{
                    OrchestratorName = 'OnboardingOrchestrator'
                    Batch            = @($Item)
                }
                $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
            }

            $Steps = $TenantOnboarding.OnboardingSteps | ConvertFrom-Json
            $OnboardingSteps = foreach ($Step in $Steps.PSObject.Properties.Name) { $Steps.$Step }
            $Relationship = try { $TenantOnboarding.Relationship | ConvertFrom-Json -ErrorAction Stop } catch { @{} }
            $Logs = try { $TenantOnboarding.Logs | ConvertFrom-Json -ErrorAction Stop } catch { @{} }
            $TenantOnboarding.OnboardingSteps = $OnboardingSteps
            $TenantOnboarding.Relationship = $Relationship
            $TenantOnboarding.Logs = $Logs
            $Results = $TenantOnboarding

            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
            $Results = "Function Error: $($_.InvocationInfo.ScriptLineNumber) - $ErrorMsg"
            $StatusCode = [HttpStatusCode]::BadRequest
        }
    } else {
        $StatusCode = [HttpStatusCode]::NotFound
        $Results = 'Relationship not found'
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}