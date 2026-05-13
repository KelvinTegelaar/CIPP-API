function Invoke-AddIntuneReusableSettingTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $GUID = $Request.Body.GUID ?? (New-Guid).GUID

    function Format-ReusableSettingCollections {
        param($InputObject)

        if ($null -eq $InputObject) { return }

        if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
            foreach ($item in $InputObject) { Format-ReusableSettingCollections -InputObject $item }
            return
        }

        if ($InputObject -is [psobject]) {
            foreach ($prop in $InputObject.PSObject.Properties) {
                if ($prop.Name -ieq 'children' -and $null -eq $prop.Value) {
                    # Graph requires children to be an array; null collections must be normalized.
                    $prop.Value = @()
                    continue
                }

                Format-ReusableSettingCollections -InputObject $prop.Value
            }
        }
    }

    try {
        $displayName = $Request.Body.displayName ?? $Request.Body.DisplayName ?? $Request.Body.displayname
        if (-not $displayName) { throw 'You must enter a displayName' }

        $description = $Request.Body.description ?? $Request.Body.Description
        $rawJsonInput = $Request.Body.rawJSON ?? $Request.Body.RawJSON ?? $Request.Body.json

        if (-not $rawJsonInput) { throw 'You must provide RawJSON for the reusable setting' }

        try {
            $parsed = $rawJsonInput | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        } catch {
            throw "RawJSON is not valid JSON: $($_.Exception.Message)"
        }

        # Normalize required collections and deep-clean Graph metadata/nulls before storing
        Format-ReusableSettingCollections -InputObject $parsed
        $cleanParsed = Remove-CIPPReusableSettingMetadata -InputObject $parsed
        $sanitizedJson = ($cleanParsed | ConvertTo-Json -Depth 100 -Compress)

        $entity = [pscustomobject]@{
            DisplayName = $displayName
            Description = $description
            RawJSON     = $sanitizedJson
            GUID        = $GUID
        } | ConvertTo-Json -Depth 100 -Compress

        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{
            JSON         = "$entity"
            RowKey       = "$GUID"
            PartitionKey = 'IntuneReusableSettingTemplate'
            GUID         = "$GUID"
            DisplayName  = $displayName
            Description  = $description
            RawJSON      = "$sanitizedJson" # ensure string serialization for table storage
        }

        Write-LogMessage -headers $Headers -API $APINAME -message "Created Intune reusable setting template named $displayName with GUID $GUID" -Sev 'Debug'
        $body = [pscustomobject]@{ Results = 'Successfully added reusable setting template' }
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APINAME -message "Reusable Settings Template creation failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $body = [pscustomobject]@{ Results = "Reusable Settings Template creation failed: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $body
        })
}
