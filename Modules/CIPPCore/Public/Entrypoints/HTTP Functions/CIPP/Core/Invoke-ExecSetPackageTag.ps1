using namespace System.Net

function Invoke-ExecSetPackageTag {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    $Table = Get-CippTable -tablename 'templates'

    try {
        $GUIDS = $Request.body.GUID
        $PackageName = $Request.body.Package | Select-Object -First 1
        foreach ($GUID in $GUIDS) {
            $Filter = "RowKey eq '$GUID'"
            $Template = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = $Template.JSON
                RowKey       = "$GUID"
                PartitionKey = $Template.PartitionKey
                GUID         = "$GUID"
                Package      = "$PackageName"
            } -Force

            Write-LogMessage -headers $Headers -API $APIName -message "Successfully updated template with GUID $GUID with package tag: $PackageName" -Sev 'Info'
        }

        $body = [pscustomobject]@{ 'Results' = "Successfully updated template(s) with package tag: $PackageName" }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to set package tag: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $body = [pscustomobject]@{'Results' = "Failed to set package tag: $($ErrorMessage.NormalizedError)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })
}
