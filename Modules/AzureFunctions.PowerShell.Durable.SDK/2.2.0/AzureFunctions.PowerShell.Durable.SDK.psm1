#
# Copyright (c) Microsoft. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.
#

using namespace System.Net

# Set aliases for cmdlets to export
Set-Alias -Name Wait-ActivityFunction -Value Wait-DurableTask
Set-Alias -Name Invoke-ActivityFunction -Value Invoke-DurableActivity
Set-Alias -Name New-OrchestrationCheckStatusResponse -Value New-DurableOrchestrationCheckStatusResponse
Set-Alias -Name Start-NewOrchestration -Value Start-DurableOrchestration
Set-Alias -Name New-DurableRetryOptions -Value New-DurableRetryPolicy

function GetDurableClientFromModulePrivateData {
    $PrivateData = $PSCmdlet.MyInvocation.MyCommand.Module.PrivateData
    if ($null -eq $PrivateData -or $null -eq $PrivateData['DurableClient']) {
        throw "Could not find `DurableClient` private data. This can occur when you have not set application setting 'ExternalDurablePowerShellSDK' to 'true' or if you're using a DurableClient CmdLet but have no DurableClient binding declared in `function.json`."
    }
    else {
        $PrivateData['DurableClient']
    }
}

function GetInvocationIdFromModulePrivateData {
    $PrivateData = $PSCmdlet.MyInvocation.MyCommand.Module.PrivateData
    if ($null -eq $PrivateData -or $null -eq $PrivateData['InvocationId']) {
        return $null
    }
    else {
        return $PrivateData['InvocationId']
    }
}

function Get-DurableStatus {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceId,

        [Parameter(
            ValueFromPipelineByPropertyName = $true)]
        [object] $DurableClient,

        [switch] $ShowHistory,

        [switch] $ShowHistoryOutput,

        [switch] $ShowInput
    )

    $ErrorActionPreference = 'Stop'

    if ($null -eq $DurableClient) {
        $DurableClient = GetDurableClientFromModulePrivateData
    }

    $requestUrl = "$($DurableClient.rpcBaseUrl)/instances/$InstanceId"

    $query = @()
    if ($ShowHistory.IsPresent) {
        $query += "showHistory=true"
    }
    if ($ShowHistoryOutput.IsPresent) {
        $query += "showHistoryOutput=true"
    }
    if ($ShowInput.IsPresent) {
        $query += "showInput=true"
    }

    if ($query.Count -gt 0) {
        $requestUrl += "?" + [string]::Join("&", $query)
    }

    Invoke-RestMethod -Uri $requestUrl
}

function Start-DurableOrchestration {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory=$true,
            Position=0,
            ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $FunctionName,

        [Parameter(
            Position=1,
            ValueFromPipelineByPropertyName=$true)]
        [object] $InputObject,

		[Parameter(
            ValueFromPipelineByPropertyName=$true)]
        [object] $DurableClient,

        [Parameter(
            ValueFromPipelineByPropertyName=$true)]
        [string] $InstanceId,

        [Parameter(
            ValueFromPipelineByPropertyName=$true)]
        [string] $Version
    )

    $ErrorActionPreference = 'Stop'

    if ($null -eq $DurableClient) {
        $DurableClient = GetDurableClientFromModulePrivateData
    }

    if (-not $InstanceId) {
        $InstanceId = (New-Guid).Guid
    }

    $invocationId = GetInvocationIdFromModulePrivateData
    $headers = Get-TraceHeaders -InvocationId $invocationId

    $Uri =
        if ($DurableClient.rpcBaseUrl) {
            # Fast local RPC path
            "$($DurableClient.rpcBaseUrl)orchestrators/$FunctionName$($InstanceId ? "/$InstanceId" : '')"
        } else {
            # Legacy app frontend path
            $UriTemplate = $DurableClient.creationUrls.createNewInstancePostUri
            $UriTemplate.Replace('{functionName}', $FunctionName).Replace('[/{instanceId}]', "/$InstanceId")
        }

    # Add version parameter to query string if provided
    if ($Version) {
        $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
        $Uri += "$separator" + "version=$([System.Web.HttpUtility]::UrlEncode($Version))"
    }

    $Body = $InputObject | ConvertTo-Json -Compress -Depth 100
              
    $null = Invoke-RestMethod -Uri $Uri -Method 'POST' -ContentType 'application/json' -Body $Body -Headers $headers
    
    return $instanceId
}

function Get-TraceHeaders {
    param(
        [string] $InvocationId
    )

    if ($null -eq $InvocationId -or $InvocationId -eq "") {
        return @{} # Return an empty headers object
    }

    # Check if Get-CurrentActivityForInvocation is available
    if (-not (Get-Command -Name Get-CurrentActivityForInvocation -ErrorAction SilentlyContinue)) {
        Write-Warning "Get-CurrentActivityForInvocation is not available. Skipping call."
        return @{} # Return an empty headers object
    }

    $activityResponse = Get-CurrentActivityForInvocation -InvocationId $invocationId
    $activity = $activityResponse.activity

    $traceId = $activity.TraceId
    $spanId = $activity.SpanId
    $traceFlags = $activity.TraceFlags
    $traceState = $activity.TraceStateString

    $flag = "00"
    if ($null -ne $traceFlags -and $traceFlags -eq "Recorded") {
        $flag = "01"
    }

    $traceparent = "00-$traceId-$spanId-$flag"

    $headers = @{
        "traceparent" = $traceparent
        "tracestate"  = $traceState
    }

    return $headers
}

function Stop-DurableOrchestration {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceId,

        [Parameter(
            Mandatory = $true,
            Position = 1,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Reason
    )

    $ErrorActionPreference = 'Stop'

    if ($null -eq $DurableClient) {
        $DurableClient = GetDurableClientFromModulePrivateData
    }

    $requestUrl = "$($DurableClient.rpcBaseUrl)/instances/$InstanceId/terminate?reason=$([System.Web.HttpUtility]::UrlEncode($Reason))"

    Invoke-RestMethod -Uri $requestUrl -Method 'POST'
}

function Suspend-DurableOrchestration {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceId,

        [Parameter(
            Mandatory = $true,
            Position = 1,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Reason
    )

    $ErrorActionPreference = 'Stop'

    if ($null -eq $DurableClient) {
        $DurableClient = GetDurableClientFromModulePrivateData
    }

    $requestUrl = "$($DurableClient.rpcBaseUrl)/instances/$InstanceId/suspend?reason=$([System.Web.HttpUtility]::UrlEncode($Reason))"

    Invoke-RestMethod -Uri $requestUrl -Method 'POST'
}

function Resume-DurableOrchestration {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory = $true,
            Position = 0,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceId,

        [Parameter(
            Mandatory = $true,
            Position = 1,
            ValueFromPipelineByPropertyName = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Reason
    )

    $ErrorActionPreference = 'Stop'

    if ($null -eq $DurableClient) {
        $DurableClient = GetDurableClientFromModulePrivateData
    }

    $requestUrl = "$($DurableClient.rpcBaseUrl)/instances/$InstanceId/resume?reason=$([System.Web.HttpUtility]::UrlEncode($Reason))"

    Invoke-RestMethod -Uri $requestUrl -Method 'POST'
}

function IsValidUrl([uri]$Url) {
    $Url.IsAbsoluteUri -and ($Url.Scheme -in 'http', 'https')
}

function GetUrlOrigin([uri]$Url) {
    $fixedOriginUrl = New-Object System.UriBuilder
    $fixedOriginUrl.Scheme = $Url.Scheme
    $fixedOriginUrl.Host = $Url.Host
    $fixedOriginUrl.Port = $Url.Port
    $fixedOriginUrl.ToString()
}

function New-DurableOrchestrationCheckStatusResponse {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$true)]
        [object] $Request,

        [Parameter(
            Mandatory=$true,
            ValueFromPipelineByPropertyName=$true)]
        [string] $InstanceId,

		[Parameter(
            ValueFromPipelineByPropertyName=$true)]
        [object] $DurableClient
    )

    if ($null -eq $DurableClient) {
        $DurableClient = GetDurableClientFromModulePrivateData
    }

    [uri]$requestUrl = $Request.Url
    $requestHasValidUrl = IsValidUrl $requestUrl
    $requestUrlOrigin = GetUrlOrigin $requestUrl
    
    $httpManagementPayload = [ordered]@{ }
    foreach ($entry in $DurableClient.managementUrls.GetEnumerator()) {
        $value = $entry.Value
    
        if ($requestHasValidUrl -and (IsValidUrl $value)) {
            $dataOrigin = GetUrlOrigin $value
            $value = $value.Replace($dataOrigin, $requestUrlOrigin)
        }
      
        $value = $value.Replace($DurableClient.managementUrls.id, $InstanceId)
        $httpManagementPayload.Add($entry.Name, $value)
    }
    
    [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::Accepted
        Body = $httpManagementPayload
        Headers = @{
            'Content-Type' = 'application/json'
            'Location' = $httpManagementPayload.statusQueryGetUri
            'Retry-After' = 10
        }
    }
}

function Send-DurableExternalEvent {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory=$true,
            Position=0,
            ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceId,

        [Parameter(
            Mandatory=$true,
            Position=1,
            ValueFromPipelineByPropertyName=$true)]
        [string] $EventName,

        [Parameter(
            Position=2,
            ValueFromPipelineByPropertyName=$true)]
        [object] $EventData,

		[Parameter(
            ValueFromPipelineByPropertyName=$true)]
        [string] $TaskHubName,

        [Parameter(
            ValueFromPipelineByPropertyName=$true)]
        [string] $ConnectionName
    )
    
    $DurableClient = GetDurableClientFromModulePrivateData

    $RequestUrl = GetRaiseEventUrl -DurableClient $DurableClient -InstanceId $InstanceId -EventName $EventName -TaskHubName $TaskHubName -ConnectionName $ConnectionName

    $Body = $EventData | ConvertTo-Json -Compress -Depth 100
              
    $null = Invoke-RestMethod -Uri $RequestUrl -Method 'POST' -ContentType 'application/json' -Body $Body
}

function GetRaiseEventUrl(
    $DurableClient,
    [string] $InstanceId,
    [string] $EventName,
    [string] $TaskHubName,
    [string] $ConnectionName) {

    $RequestUrl = $DurableClient.rpcBaseUrl + "/instances/$InstanceId/raiseEvent/$EventName"
    
    $query = @()
    if ($null -eq $TaskHubName) {
        $query += "taskHub=$TaskHubName"
    }
    if ($null -eq $ConnectionName) {
        $query += "connection=$ConnectionName"
    }
    if ($query.Count -gt 0) {
        $RequestUrl += "?" + [string]::Join("&", $query)
    }

    return $RequestUrl
}