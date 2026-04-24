function Invoke-AddIntuneReusableSetting {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $Tenant = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $TemplateId = $Request.Body.TemplateId ?? $Request.Body.TemplateList?.value ?? $Request.Body.TemplateList ?? $Request.Query.TemplateId

    # Normalize tenant filter (UI sends an array of objects with value/defaultDomainName)
    if ($Tenant -is [System.Collections.IEnumerable] -and -not ($Tenant -is [string])) {
        $Tenant = @($Tenant)[0]
    }

    $Tenant = $Tenant.value ?? $Tenant.addedFields?.defaultDomainName ?? $Tenant

    if (-not $Tenant) {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required' }
            })
    }

    if (-not $TemplateId) {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{ Results = 'TemplateId is required' }
            })
    }

    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'IntuneReusableSettingTemplate' and RowKey eq '$TemplateId'"
        $TemplateEntity = Get-CIPPAzDataTableEntity @Table -Filter $Filter
        if (-not $TemplateEntity) {
            return ([HttpResponseContext]@{
                    StatusCode = [System.Net.HttpStatusCode]::NotFound
                    Body       = @{ Results = "Template $TemplateId not found" }
                })
        }

        $TemplateJson = $TemplateEntity.RawJSON
        if (-not $TemplateJson) {
            $ParsedEntity = $TemplateEntity.JSON | ConvertFrom-Json -Depth 200 -ErrorAction SilentlyContinue
            $TemplateJson = $ParsedEntity.RawJSON
        }
        if (-not $TemplateJson) { throw "Template $TemplateId has no RawJSON" }

        try {
            $BodyObject = $TemplateJson | ConvertFrom-Json -ErrorAction Stop
        } catch {
            throw "Template JSON is invalid: $($_.Exception.Message)"
        }

        $displayName = $BodyObject.displayName ?? $TemplateId

        $ExistingSettings = New-GraphGETRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings' -tenantid $Tenant
        $ExistingMatch = @($ExistingSettings) | Where-Object { $_.displayName -eq $displayName } | Select-Object -First 1

        $compare = $null
        if ($ExistingMatch) {
            try {
                $ExistingSanitized = $ExistingMatch | Select-Object -Property * -ExcludeProperty id, createdDateTime, lastModifiedDateTime, version, '@odata.context'
                $compare = Compare-CIPPIntuneObject -ReferenceObject $BodyObject -DifferenceObject $ExistingSanitized -compareType 'ReusablePolicySetting' -ErrorAction SilentlyContinue
            } catch {
                $compare = $null
            }
        }

        if ($ExistingMatch -and -not $compare) {
            $message = "Reusable setting '$displayName' is already compliant."
            Write-LogMessage -headers $Headers -API $APIName -message $message -Sev 'Info'
            return ([HttpResponseContext]@{
                    StatusCode = [System.Net.HttpStatusCode]::OK
                    Body       = @{ Results = $message; Id = $ExistingMatch.id }
                })
        }

        if ($ExistingMatch) {
            $null = New-GraphPOSTRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings/$($ExistingMatch.id)" -tenantid $Tenant -type PUT -body $TemplateJson
            $Result = "Updated reusable setting '$displayName' in tenant $Tenant"
        } else {
            $Create = New-GraphPOSTRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/reusablePolicySettings' -tenantid $Tenant -type POST -body $TemplateJson
            $Result = "Created reusable setting '$displayName' in tenant $Tenant"
        }

        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body       = @{ Results = $Result }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $logMessage = "Reusable settings deployment failed: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $logMessage -Sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::InternalServerError
                Body       = @{ Results = $logMessage }
            })
    }
}
