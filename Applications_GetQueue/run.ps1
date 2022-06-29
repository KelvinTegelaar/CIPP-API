param($name)

if (Test-Path '.\ChocoApps.Cache') {
    $object = (Get-ChildItem '.\ChocoApps.Cache\*' | Where-Object { $_.name -ne 'CurrentlyRunning.txt' }).name 
}
else {
    $object = @()
}
$object