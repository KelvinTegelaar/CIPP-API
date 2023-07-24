function Set-CIPPMailboxArchive {
    [CmdletBinding()]
    param (
        $ExecutingUser,
        $userid,
        $username,
        $APIName = "Mailbox Archive",
        $TenantFilter,
        [bool]$ArchiveEnabled
    )

    Try {
        if (!$username) { $username = $userid }
        New-ExoRequest -tenantid $TenantFilter -cmdlet "Enable-Mailbox" -cmdParams @{Identity = $userid; Archive = $ArchiveEnabled }
        "Successfully set archive for $username to $ArchiveEnabled"
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Successfully set archive for $username to $ArchiveEnabled" -Sev "Info"
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($tenantfilter) -message "Failed to set archive $($_.Exception.Message)" -Sev "Error"
        "Failed. $($_.Exception.Message)" 
    }
}
