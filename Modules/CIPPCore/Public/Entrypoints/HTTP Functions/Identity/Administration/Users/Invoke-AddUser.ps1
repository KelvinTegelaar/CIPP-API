using namespace System.Net

function Invoke-AddUser {
    <#
    .SYNOPSIS
    Add new users to Microsoft 365 tenants
    
    .DESCRIPTION
    Creates new users in Microsoft 365 tenants with optional scheduling and post-execution notifications
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
        
    .NOTES
    Group: Identity Management
    Summary: Add User
    Description: Creates new users in Microsoft 365 tenants with support for immediate creation or scheduled tasks
    Tags: Identity,Users,Administration
    Parameter: UserObj (object) [body] - User object containing all user properties and configuration
    Parameter: Scheduled.Enabled (boolean) [body] - Whether to schedule the user creation for later
    Parameter: Scheduled.date (string) [body] - Date and time for scheduled user creation
    Parameter: PostExecution.Webhook (boolean) [body] - Send webhook notification after execution
    Parameter: PostExecution.Email (boolean) [body] - Send email notification after execution
    Parameter: PostExecution.PSA (boolean) [body] - Send PSA notification after execution
    Response: Returns a response object with the following properties:
    Response: - Results (array): Array of result messages indicating success or failure
    Response: - CopyFrom (object): Copy operation results with Success and Error properties
    Response: When scheduled task is created:
    Response: - Results (array): Array containing success message about scheduled task creation
    Response: When immediate creation is performed:
    Response: - Results (array): Array containing creation results, password information, and status
    Response: - CopyFrom (object): Copy operation results with Success and Error properties
    Example: {
      "Results": [
        "Successfully created user John Doe",
        "User account enabled successfully",
        {
          "resultText": "User created successfully. Temporary password: TempPass123!",
          "copyField": "TempPass123!",
          "state": "success"
        }
      ],
      "CopyFrom": {
        "Success": ["Successfully copied group memberships"],
        "Error": []
      }
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $UserObj = $Request.Body

    if ($UserObj.Scheduled.Enabled) {
        $TaskBody = [pscustomobject]@{
            TenantFilter  = $UserObj.tenantFilter
            Name          = "New user creation: $($UserObj.mailNickname)@$($UserObj.PrimDomain.value)"
            Command       = @{
                value = 'New-CIPPUserTask'
                label = 'New-CIPPUserTask'
            }
            Parameters    = [pscustomobject]@{ UserObj = $UserObj }
            ScheduledTime = $UserObj.Scheduled.date
            PostExecution = @{
                Webhook = [bool]$Request.Body.PostExecution.Webhook
                Email   = [bool]$Request.Body.PostExecution.Email
                PSA     = [bool]$Request.Body.PostExecution.PSA
            }
        }
        Add-CIPPScheduledTask -Task $TaskBody -hidden $false -DisallowDuplicateName $true -Headers $Headers
        $body = [pscustomobject] @{
            'Results' = @("Successfully created scheduled task to create user $($UserObj.DisplayName)")
        }
    }
    else {
        $CreationResults = New-CIPPUserTask -UserObj $UserObj -APIName $APIName -Headers $Headers
        $body = [pscustomobject] @{
            'Results'  = @(
                $CreationResults.Results[0],
                $CreationResults.Results[1],
                @{
                    'resultText' = $CreationResults.Results[2]
                    'copyField'  = $CreationResults.password
                    'state'      = 'success'
                }
            )
            'CopyFrom' = @{
                'Success' = $CreationResults.CopyFrom.Success
                'Error'   = $CreationResults.CopyFrom.Error
            }
        }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}
