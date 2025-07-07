using namespace System.Net

function Invoke-AddStandardsDeploy {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $user = $Headers.'x-ms-client-principal'
    $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails

    try {
        $Tenant = $Request.Body.tenant
        $Settings = ($Request.Body | Select-Object -Property * -ExcludeProperty Select_*, None )
        $Settings | Add-Member -NotePropertyName 'v2.1' -NotePropertyValue $true -Force
        if ($Settings.phishProtection.remediate) {
            $URL = $Headers.'x-ms-original-url'.split('/api') | Select-Object -First 1
            Write-Host $URL
            $Settings.phishProtection = [pscustomobject]@{
                remediate = [bool]$Settings.phishProtection.remediate
                URL       = $URL
            }
        }
        #Get all subobjects in $Settings that are set to false, and remove them.
        $Settings.PSObject.Properties.Name | Where-Object { $Settings.$_ -eq $false -and $_ -ne 'v2.1' -and $_ -in 'Alert', 'Remediate', 'Report' } | ForEach-Object {
            $Settings.PSObject.Properties.Remove($_)
        }

        $Object = [PSCustomObject]@{
            Tenant    = $Tenant
            AddedBy   = $username
            AppliedAt = (Get-Date).ToString('s')
            Standards = $Settings
            v2        = $true
        } | ConvertTo-Json -Depth 10

        $Table = Get-CippTable -tablename 'standards'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$Object"
            RowKey       = "$Tenant"
            PartitionKey = 'standards'
        }
        Write-LogMessage -headers $Headers -tenant $Tenant -API 'Standards' -message 'Successfully added standards deployment' -Sev 'Info'

        $Result = 'Successfully added standards deployment'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to add standard: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API 'Standards' -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Result }
    }
}
