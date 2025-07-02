using namespace System.Net

function Invoke-ListMFAUsers {
    <#
    .SYNOPSIS
    List Multi-Factor Authentication (MFA) users and their status
    
    .DESCRIPTION
    Retrieves MFA status and methods for users in Microsoft 365 tenants with support for single tenant or all tenants with caching
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
        
    .NOTES
    Group: Identity Management
    Summary: List MFA Users
    Description: Retrieves Multi-Factor Authentication (MFA) status and methods for users in Microsoft 365 tenants with support for single tenant queries or all tenants with background processing and caching
    Tags: Identity,MFA,Authentication,Reports
    Parameter: tenantFilter (string) [query] - Target tenant identifier (use 'AllTenants' for all tenants)
    Response: Returns an array of MFA user objects with the following properties:
    Response: - UPN (string): User Principal Name
    Response: - DisplayName (string): User display name
    Response: - MFAMethods (array): Array of MFA methods configured for the user
    Response: - CAPolicies (array): Conditional Access policies affecting the user
    Response: - MFAStatus (string): Overall MFA status (Enabled, Disabled, etc.)
    Response: - LastSignIn (string): Last sign-in date and time
    Response: For AllTenants with no cache: Returns loading message and initiates background processing
    Example: [
      {
        "UPN": "john.doe@contoso.com",
        "DisplayName": "John Doe",
        "MFAMethods": [
          {
            "methodType": "Microsoft Authenticator",
            "default": true
          }
        ],
        "CAPolicies": [
          {
            "displayName": "Require MFA for all users",
            "state": "enabled"
          }
        ],
        "MFAStatus": "Enabled",
        "LastSignIn": "2024-01-15T10:30:00Z"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    if ($TenantFilter -ne 'AllTenants') {
        $GraphRequest = Get-CIPPMFAState -TenantFilter $TenantFilter
    }
    else {
        $Table = Get-CIPPTable -TableName cachemfa

        $Rows = Get-CIPPAzDataTableEntity @Table | Where-Object -Property Timestamp -GT (Get-Date).AddHours(-2)
        if (!$Rows) {
            $TenantList = Get-Tenants -IncludeErrors
            $Queue = New-CippQueueEntry -Name 'MFA Users - All Tenants' -Link '/identity/reports/mfa-report?customerId=AllTenants' -TotalTasks ($TenantList | Measure-Object).Count
            Write-Information ($Queue | ConvertTo-Json)
            $GraphRequest = [PSCustomObject]@{
                UPN = 'Loading data for all tenants. Please check back in a few minutes'
            }
            $Batch = $TenantList | ForEach-Object {
                $_ | Add-Member -NotePropertyName FunctionName -NotePropertyValue 'ListMFAUsersQueue'
                $_ | Add-Member -NotePropertyName QueueId -NotePropertyValue $Queue.RowKey
                $_
            }
            if (($Batch | Measure-Object).Count -gt 0) {
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'ListMFAUsersOrchestrator'
                    Batch            = @($Batch)
                    SkipLog          = $true
                }
                #Write-Host ($InputObject | ConvertTo-Json)
                $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                Write-Host "Started permissions orchestration with ID = '$InstanceId'"
            }
        }
        else {
            $Rows = foreach ($Row in $Rows) {
                if ($Row.CAPolicies) {
                    $Row.CAPolicies = try { $Row.CAPolicies | ConvertFrom-Json } catch { $Row.CAPolicies }
                }
                if ($Row.MFAMethods) {
                    $Row.MFAMethods = try { $Row.MFAMethods | ConvertFrom-Json } catch { $Row.MFAMethods }
                }
                $Row
            }
            $GraphRequest = $Rows
        }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}
