$Tenant = '7ngn50.onmicrosoft.com'
$item =0
Get-ChildItem "C:\Github\CIPP-API\Modules\CIPPCore\Public\Tests\Invoke-CippTest*.ps1" | ForEach-Object {
    $item++

    write-host "performing test $($_.BaseName) - $($item)"
    . $_.FullName; & $_.BaseName -Tenant $Tenant

}
