function Invoke-ListDefenderTVM {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists software vulnerabilities from Microsoft Defender Threat and Vulnerability Management (TVM), grouped by CVE ID.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    # Interact with query parameters or the body of the request.
    try {
        # Fold the streamed export into one bucket per CVE as records arrive, rather than grouping
        # every device x CVE record in memory. Per property the bucket keeps the lowest non-null
        # value (arrays flattened), which is what sorting the group's values and taking the first did.
        $Buckets = @{}
        Get-DefenderTvmRaw -TenantId $TenantFilter -Stream | ForEach-Object {
            $CveId = [string]$_.cveId
            $Bucket = $Buckets[$CveId]
            if (-not $Bucket) {
                $Bucket = @{ Count = 0; Devices = [System.Collections.Generic.List[object]]::new(); Values = @{} }
                $Buckets[$CveId] = $Bucket
            }
            $Bucket.Count++
            foreach ($Property in $_.PSObject.Properties) {
                if ($Property.Name -eq 'deviceName') {
                    foreach ($Name in @($Property.Value)) { $Bucket.Devices.Add(@{ deviceName = $Name }) }
                    continue
                }
                if (-not $Bucket.Values.ContainsKey($Property.Name)) { $Bucket.Values[$Property.Name] = $null }
                foreach ($Value in @($Property.Value)) {
                    if ($null -ne $Value -and ($null -eq $Bucket.Values[$Property.Name] -or $Value -lt $Bucket.Values[$Property.Name])) {
                        $Bucket.Values[$Property.Name] = $Value
                    }
                }
            }
        }

        $GroupObj = foreach ($CveId in ($Buckets.Keys | Sort-Object)) {
            $Bucket = $Buckets[$CveId]
            $obj = [ordered]@{
                customerId           = $TenantFilter
                affectedDevicesCount = $Bucket.Count
                cveId                = $CveId
                affectedDevices      = @($Bucket.Devices)
            }
            foreach ($Property in ($Bucket.Values.Keys | Sort-Object)) {
                $obj[$Property] = $Bucket.Values[$Property]
            }

            # Convert and output as PSCustomObject. Not really needed, but hey, why not.
            [pscustomobject]$obj
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GroupObj = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GroupObj)
        })

}
