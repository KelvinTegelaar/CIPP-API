using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."

# Input bindings are passed in via param block.
$Tenants = ($Request.body | Select-Object Select_*).psobject.properties.value
if ("AllTenants" -in $Tenants) { $Tenants = (Get-Tenants).defaultDomainName }
$AssignTo = if ($request.body.Assignto -ne "on") { $request.body.Assignto }

$results = foreach ($Tenant in $tenants) {
    try {
        $ExistingO365 = New-graphGetRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" -tenantid $tenant | Where-Object { $_.displayname -eq "Mifcrosoft 365 Apps for Windows 10 and later" }
        if (!$ExistingO365) {
            $Arch = if ($request.body.arch) { "x64" } else { "x86" }
            $products = @("o365ProPlusRetail")
            $ExcludedApps = [pscustomobject]@{
                infoPath           = $true
                sharePointDesigner = $true
                excel              = $false
                lync               = $false
                oneNote            = $false
                outlook            = $false
                powerPoint         = $false
                publisher          = $false
                teams              = $false
                word               = $false
                access             = $false
                bing               = $false
            }
            foreach ($ExcludedApp in $request.body.excludedApps.value) {
                $ExcludedApps.$excludedapp = $true
            }
            $ObjBody = [pscustomobject]@{
                "@odata.type"                          = "#microsoft.graph.officeSuiteApp"
                "displayName"                          = "Microsoft 365 Apps for Windows 10 and later"
                "description"                          = "Microsoft 365 Apps for Windows 10 and later"
                "informationUrl"                       = "https://products.office.com/en-us/explore-office-for-home"
                "isFeatured"                           = $true
                "publisher"                            = "Microsoft"
                "notes"                                = ""
                "owner"                                = "Microsoft"
                "autoAcceptEula"                       = [bool]$request.body.AcceptLicense
                "excludedApps"                         = $ExcludedApps
                "officePlatformArchitecture"           = $Arch
                "officeSuiteAppDefaultFileFormat"      = "OfficeOpenXMLFormat"
                "localesToInstall"                     = @($request.body.languages.value)
                "shouldUninstallOlderVersionsOfOffice" = [bool]$request.body.RemoveVersions
                "updateChannel"                        = $request.body.updateChannel.value
                "useSharedComputerActivation"          = [bool]$request.body.SharedComputerActivation
                "productIds"                           = $products
                "largeIcon"                            = @{ 
                    "type"  = "image/png"
                    "value" = "iVBORw0KGgoAAAANSUhEUgAAAF0AAAAeCAMAAAEOZNKlAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAJhUExURf////7z7/i9qfF1S/KCW/i+qv3q5P/9/PrQwfOMae1RG+s8AOxGDfBtQPWhhPvUx/759/zg1vWgg+9fLu5WIvKFX/rSxP728/nCr/FyR+tBBvOMaO1UH+1RHOs+AvSScP3u6f/+/v3s5vzg1+xFDO9kNPOOa/i7pvzj2/vWyes9Af76+Pzh2PrTxf/6+f7y7vOGYexHDv3t5+1SHfi8qPOIZPvb0O1NFuxDCe9hMPSVdPnFs/3q4/vaz/STcu5VIe5YJPWcfv718v/9/e1MFfF4T/F4TvF2TP3o4exECvF0SexIEPONavzn3/vZze1QGvF3Te5dK+5cKvrPwPrQwvKAWe1OGPexmexKEveulfezm/BxRfamiuxLE/apj/zf1e5YJfSXd/OHYv3r5feznPakiPze1P7x7f739f3w6+xJEfnEsvWdf/Wfge1LFPe1nu9iMvnDsfBqPOs/BPOIY/WZevJ/V/zl3fnIt/vTxuxHD+xEC+9mN+5ZJv749vBpO/KBWvBwRP/8+/SUc/etlPjArP/7+vOLZ/F7UvWae/708e1OF/aihvSWdvi8p+tABfSZefvVyPWihfSVde9lNvami+9jM/zi2fKEXvBuQvOKZvalifF5UPJ/WPSPbe9eLfrKuvvd0uxBB/7w7Pzj2vrRw/rOv+1PGfi/q/eymu5bKf3n4PnJuPBrPf3t6PWfgvWegOxCCO9nOO9oOfaskvSYePi5pPi2oPnGtO5eLPevlvKDXfrNvv739Pzd0/708O9gL+9lNfJ9VfrLu/OPbPnDsPBrPus+A/nArfarkQAAAGr5HKgAAADLdFJOU/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////8AvuakogAAAAlwSFlzAAAOwwAADsMBx2+oZAAAAz5JREFUOE+tVTtu4zAQHQjppmWzwIJbEVCzpTpjbxD3grQHSOXKRXgCAT6EC7UBVAmp3KwBnmvfzNCyZTmxgeTZJsXx43B+HBHRE34ZkXgkerXFTheeiCkRrbB4UXmp4wSWz5raaQEMTM5TZwuiXoaKgV+6FsmkZQcSy0kA71yMTMGHanX+AzMMGLAQCxU1F/ZwjULPugazl82GM0NEKm/U8EqFwEkO3/EAT4grgl0nucwlk9pcpTTJ4VPA4g/Rb3yIRhhp507e9nTQmZ1OS5RO4sS7nIRPEeHXCHdkw9ZEW2yVE5oIS7peD58Avs7CN+PVCmHh21oOqBdjDzIs+FldPJ74TFESUSJEfVzy9U/dhu+AuOT6eBp6gGKyXEx8euO450ZE4CMfstMFT44broWw/itkYErWXRx+fFArt9Ca9os78TFed0LVIUsmIHrwbwaw3BEOnOk94qVpQ6Ka2HjxewJnfyd6jUtGDQLdWlzmYNYLeKbbGOucJsNabCq1Yub0o92rtR+i30V2dapxYVEePXcOjeCKPnYyit7BtKeNlZqHbr+gt7i+AChWA9RsRs03pxTQc67ouWpxyESvjK5Vs3DVSy3IpkxPm5X+wZoBi+MFHWW69/w8FRhc7VBe6HAhMB2b8Q0XqDzTNZtXUMnKMjwKVaCrB/CSUL7WSx/HsdJC86lFGXwnioTeOMPjV+szlFvrZLA5VMVK4y+41l4e1xfx7Z88o4hkilRUH/qKqwNVlgDgpvYCpH3XwAy5eMCRnezIUxffVXoDql2rTHFDO+pjWnTWzAfrYXn6BFECblUpWGrvPZvBipETjS5ydM7tdXpH41ZCEbBNy/+wFZu71QO2t9pgT+iZEf657Q1vpN94PQNDxUHeKR103LV9nPVOtDikcNKO+2naCw7yKBhOe9Hm79pe8C4/CfC2wDjXnqC94kEeBU3WwN7dt/2UScXas7zDl5GpkY+M8WKv2J7fd4Ib2rGTk+jsC2cleEM7jI9veF7B0MBJrsZqfKd/81q9pR2NZfwJK2JzsmIT1Ns8jUH0UusQBpU8d2JzsHiXg1zXGLqxfitUNTDT/nUUeqDBp2HZVr+Ocqi/Ty3Rf4Jn82xxfSNtAAAAAElFTkSuQmCC"
                }
            }
            Write-Host ($ObjBody | ConvertTo-Json -Compress)
            $OfficeAppID = New-graphPostRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" -tenantid $tenant -Body (ConvertTo-Json -InputObject $ObjBody -Depth 10) -type POST
        }
        else { 
            "Office deployment already exists for $($Tenant)"
            Continue
        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($tenant) -message "Added Office profile to $($tenant)" -Sev "Info"
        if ($AssignTo) {
            $AssignO365 = if ($AssignTo -ne "AllDevicesAndUsers") { '{"mobileAppAssignments":[{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.' + $($AssignTo) + 'AssignmentTarget"},"intent":"Required"}]}' } else { '{"mobileAppAssignments":[{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allDevicesAssignmentTarget"},"intent":"Required"},{"@odata.type":"#microsoft.graph.mobileAppAssignment","target":{"@odata.type":"#microsoft.graph.allLicensedUsersAssignmentTarget"},"intent":"Required"}]}' }           Write-Host ($AssignO365)
            New-graphPostRequest -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($OfficeAppID.id)/assign" -tenantid $tenant -Body $AssignO365 -type POST
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -tenant $($tenant) -message "Assigned Office to $AssignTo" -Sev "Info"
        }
        "Successfully added Office Application for $($Tenant)"
    }
    catch {
        "Failed to add Office App for $($Tenant): $($_.Exception.Message)"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName  -tenant $($tenant)  -message "Failed adding Autopilot Profile $($Displayname). Error: $($_.Exception.Message)" -Sev "Error"
        continue
    }

}

$body = [pscustomobject]@{"Results" = $results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })


