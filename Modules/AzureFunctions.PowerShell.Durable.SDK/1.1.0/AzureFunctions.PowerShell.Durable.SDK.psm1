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

<#
.SYNOPSIS
    Start an orchestration Azure Function.
.DESCRIPTION
    Start an orchestration Azure Function with the given function name and input value.
.EXAMPLE
    PS > Start-DurableOrchestration -DurableClient Starter -FunctionName OrchestratorFunction -InputObject "input value for the orchestration function"
    Return the instance id of the new orchestration.
.PARAMETER FunctionName
    The name of the orchestration Azure Function you want to start.
.PARAMETER InputObject
    The input value that will be passed to the orchestration Azure Function.
.PARAMETER DurableClient
    The orchestration client object.
#>
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
        [string] $InstanceId
    )

    $ErrorActionPreference = 'Stop'

    if ($null -eq $DurableClient) {
        $DurableClient = GetDurableClientFromModulePrivateData
    }

    if (-not $InstanceId) {
        $InstanceId = (New-Guid).Guid
    }

    $Uri =
        if ($DurableClient.rpcBaseUrl) {
            # Fast local RPC path
            "$($DurableClient.rpcBaseUrl)orchestrators/$FunctionName$($InstanceId ? "/$InstanceId" : '')"
        } else {
            # Legacy app frontend path
            $UriTemplate = $DurableClient.creationUrls.createNewInstancePostUri
            $UriTemplate.Replace('{functionName}', $FunctionName).Replace('[/{instanceId}]', "/$InstanceId")
        }

    $Body = $InputObject | ConvertTo-Json -Compress -Depth 100
              
    $null = Invoke-RestMethod -Uri $Uri -Method 'POST' -ContentType 'application/json' -Body $Body
    
    return $instanceId
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

<#
.SYNOPSIS
    Send an external event to an orchestration instance.
.DESCRIPTION
    Send an external event with the given event name, and event data to an orchestration instance with the given instance ID.
.EXAMPLE
    PS > Send-DurableExternalEvent -InstanceId "example-instance-id" -EventName "ExampleExternalEvent" -EventData "data for the external event"
    Return the instance id of the new orchestration.
.PARAMETER InstanceId
    The ID of the orchestration instance that will handle the external event.
.PARAMETER EventName
    The name of the external event.
.PARAMETER EventData
    The JSON-serializable data associated with the external event.
.PARAMETER TaskHubName
    The TaskHubName of the orchestration instance that will handle the external event.
.PARAMETER ConnectionName
    The name of the connection string associated with TaskHubName
#>
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