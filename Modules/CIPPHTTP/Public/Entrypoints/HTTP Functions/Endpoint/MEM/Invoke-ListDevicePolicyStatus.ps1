function Invoke-ListDevicePolicyStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists the configuration, compliance and enrollment policies applied to one Intune managed device and their status, using the same reports as the device page in Intune. report=all returns all three in one response, with a per-report error when one fails. Configuration covers device configuration profiles, settings catalog, administrative templates and endpoint security policies.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # Intune managed device id (GUID)
    $DeviceId = $Request.Query.deviceId
    # Which report to read: configuration, compliance, or all for both in one response
    $Report = $Request.Query.report

    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'deviceId is required.' }
            })
    }

    # The id goes into an OData filter, so only a bare GUID is accepted
    $ParsedId = [guid]::Empty
    if (-not [guid]::TryParse("$DeviceId", [ref]$ParsedId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'deviceId must be an Intune managed device id.' }
            })
    }
    $DeviceGuid = $ParsedId.ToString()

    $PolicyTypes = @(
        'Microsoft.Management.Services.Api.DeviceConfiguration'
        'DeviceManagementConfigurationPolicy'
        'DeviceConfigurationAdmxPolicy'
        'Microsoft.Management.Services.Api.DeviceManagementIntent'
    )
    $TypeFilter = ($PolicyTypes | ForEach-Object { "(PolicyBaseTypeName eq '$_')" }) -join ' or '
    $Reports = [ordered]@{
        configuration = @{
            Uri    = 'https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPoliciesReportForDevice'
            Filter = "($TypeFilter) and (IntuneDeviceId eq '$DeviceGuid')"
        }
        compliance    = @{
            Uri    = 'https://graph.microsoft.com/beta/deviceManagement/reports/getDevicePoliciesComplianceReport'
            Filter = "(DeviceId eq '$DeviceGuid')"
        }
        enrollment    = @{
            Uri     = 'https://graph.microsoft.com/beta/deviceManagement/reports/getEnrollmentConfigurationPoliciesByDevice'
            Filter  = "(DeviceId eq '$DeviceGuid')"
            Select  = @('PolicyId', 'PolicyType', 'ProfileName')
            OrderBy = @()
        }
    }

    if ($Report -ne 'all' -and -not $Reports.Contains("$Report")) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'report must be configuration, compliance, enrollment or all.' }
            })
    }

    $GetReportRows = {
        param($Definition)
        $Rows = [System.Collections.Generic.List[object]]::new()
        $PageSize = 500
        $Skip = 0
        do {
            $Body = @{
                top     = $PageSize
                skip    = $Skip
                select  = $Definition.Select ?? @()
                orderBy = $Definition.OrderBy ?? @('PolicyName')
                search  = ''
                filter  = $Definition.Filter
            } | ConvertTo-Json -Compress -Depth 5
            $Page = New-GraphPOSTRequest -uri $Definition.Uri -tenantid $TenantFilter -body $Body
            if ($Page -is [string]) { $Page = $Page | ConvertFrom-Json }

            # Reports come back as a column schema plus positional value arrays
            $Columns = @($Page.Schema.Column)
            foreach ($Values in @($Page.Values)) {
                $Row = [ordered]@{}
                for ($Index = 0; $Index -lt $Columns.Count; $Index++) {
                    $Row[$Columns[$Index]] = $Values[$Index]
                }
                $Rows.Add([PSCustomObject]$Row)
            }
            $Skip = $Skip + $PageSize
        } while (@($Page.Values).Count -eq $PageSize -and $Skip -lt [int]$Page.TotalRowCount)
        , @($Rows)
    }

    $Names = if ($Report -eq 'all') { @($Reports.Keys) } else { @("$Report") }
    $Loaded = [ordered]@{}
    $Errors = [ordered]@{}
    foreach ($Name in $Names) {
        try {
            $Loaded[$Name] = & $GetReportRows $Reports[$Name]
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Errors[$Name] = "Failed to load $Name policies for device $($DeviceId): $($ErrorMessage.NormalizedError)"
        }
    }

    if ($Report -eq 'all') {
        # One round trip for the device page; a report that failed is null with its reason under errors
        $StatusCode = Get-CippBulkStatusCode -Total $Names.Count -Failed $Errors.Count
        $Results = [ordered]@{
            configuration = $Loaded['configuration']
            compliance    = $Loaded['compliance']
            enrollment    = $Loaded['enrollment']
            errors       = $Errors
        }
    } elseif ($Errors.Count -gt 0) {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = $Errors[$Report]
    } else {
        $StatusCode = [HttpStatusCode]::OK
        $Results = $Loaded[$Report]
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
