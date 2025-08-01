using namespace System.Net

function Invoke-listStandardTemplates {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Standards.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
    # Interact with query parameters or the body of the request.
    $ID = $Request.Query.id
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'StandardsTemplateV2'"
    $Templates = (Get-CIPPAzDataTableEntity @Table -Filter $Filter) | ForEach-Object {
        $JSON = $_.JSON -replace '"Action":', '"action":'
        try {
            $RowKey = $_.RowKey
            $Data = $JSON | ConvertFrom-Json -Depth 100 -ErrorAction SilentlyContinue

        } catch {
            Write-Host "$($RowKey) standard could not be loaded: $($_.Exception.Message)"
            return
        }
        if ($Data) {
            $Data | Add-Member -NotePropertyName 'GUID' -NotePropertyValue $_.GUID -Force

            if (!$Data.excludedTenants) {
                $Data | Add-Member -NotePropertyName 'excludedTenants' -NotePropertyValue @() -Force
            } else {
                if ($Data.excludedTenants -and $Data.excludedTenants -ne 'excludedTenants') {
                    $Data.excludedTenants = @($Data.excludedTenants)
                } else {
                    $Data.excludedTenants = @()
                }
            }
            $Data
        }
    } | Sort-Object -Property templateName

    if ($ID) { $Templates = $Templates | Where-Object GUID -EQ $ID }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Templates)
        })

}
