#  Build script to build the .NET and Go lang code for the Windows agent.
#  It does following  tasks
#  1. Builds the certificate generator code in .NET and copy the binaries in zip file to ..\..\kubernetes\windows\omsagentwindows
#  2. Builds the out_oms plugin code in go lang  into the shared object(.so) file and copy the out_oms.so file  to ..\..\kubernetes\windows\omsagentwindows
#  3. copy the files under installer directory to ..\..\kubernetes\windows\omsagentwindows

$dotnetcoreframework = "netcoreapp2.2"

Write-Host("Building Certificate generator code...")
$currentdir =  $PWD
if ($false -eq (Test-Path -Path $currentdir)) {
    Write-Host("Invalid current dir : " + $currentdir + " ") -ForegroundColor Red
    exit
}

$builddir = Split-Path -Path $currentdir
if ($false -eq (Test-Path -Path $builddir)) {
    Write-Host("Invalid build dir : " + $builddir + " ") -ForegroundColor Red
    exit
}

$versionFilePath = Join-Path -Path $builddir -child "version"
if ($false -eq (Test-Path -Path $versionFilePath)) {
    Write-Host("Version file path incorret or doesnt exist : " + $versionFilePath + " ") -ForegroundColor Red
    exit
}

# read the version info
foreach($line in Get-Content -Path $versionFilePath) {
    if ([string]$line.startswith("CONTAINER_BUILDVERSION_") -eq $true) {
         $parts =  $line.split("=")
         if ($parts.length -lt 2 ) {
            Write-Host("Invalid content in version file : " + $versionFilePath + " ") -ForegroundColor Red
            exit
         }
         switch ($parts[0]) {
            "CONTAINER_BUILDVERSION_MAJOR" { $BuildVersionMajor = $parts[1] }
            "CONTAINER_BUILDVERSION_MINOR" { $BuildVersionMinor = $parts[1] }
            "CONTAINER_BUILDVERSION_PATCH" { $BuildVersionPatch = $parts[1] }
            "CONTAINER_BUILDVERSION_BUILDNR" { $BuildVersionBuildNR = $parts[1] }
            "CONTAINER_BUILDVERSION_DATE" { $BuildVersionDate = $parts[1] }
            "CONTAINER_BUILDVERSION_STATUS" { $BuildVersionStatus = $parts[1] }
            default { Write-Host("This field is not expected in the version file : $line") -ForegroundColor Yellow }
        }
    }
}

if ([string]::IsNullOrEmpty($BuildVersionMajor) -or
    [string]::IsNullOrEmpty($BuildVersionMinor) -or
    [string]::IsNullOrEmpty($BuildVersionPatch) -or
    [string]::IsNullOrEmpty($BuildVersionBuildNR) -or
    [string]::IsNullOrEmpty($BuildVersionDate) -or
    [string]::IsNullOrEmpty($BuildVersionStatus)) {
    Write-Host("Expected version info doesnt exist in this version file : " + $versionFilePath + " ") -ForegroundColor Red
    exit
}
# build version format will be [major].[minior].[patch]-[revision]
$buildVersionString = $BuildVersionMajor + "." + $BuildVersionMinor + "." + $BuildVersionPatch + "-" + $BuildVersionBuildNR
$buildVersionDate = $BuildVersionDate


$certsrcdir = Join-Path -Path $builddir -ChildPath "windows\installer\certificategenerator"
if ($false -eq (Test-Path -Path $certsrcdir)) {
    Write-Host("Invalid certificate generator source dir : " + $certsrcdir + " ") -ForegroundColor Red
    exit
}
Write-Host("set the cerificate generator source code director : " + $certsrcdir + " ...")
Set-Location -Path $certsrcdir

Write-Host("Adding dotnet packages Newtonsoft.json and BouncyCastle ...")
dotnet add package Newtonsoft.json
dotnet add package BouncyCastle
Write-Host("Successfully added dotnet packages") -ForegroundColor Green
dotnet build  -f $dotnetcoreframework
Write-Host("Building Certificate generator code and ...") -ForegroundColor Green

Write-Host("Publish release and win10-x64 binaries of certificate generator code  ...")
dotnet publish -c Release -r win10-x64
Write-Host("Successfully published certificate generator code binaries") -ForegroundColor Green

$certreleasebinpath =  Join-Path -PATH $certsrcdir -ChildPath "bin\Release\$dotnetcoreframework\win10-x64\publish\*.*"
if ($false -eq (Test-Path -Path $certreleasebinpath)) {
    Write-Host("certificate release bin path doesnt exist : " + $certreleasebinpath + " ") -ForegroundColor Red
    exit
}

$rootdir = Split-Path -Path $builddir
if ($false -eq (Test-Path -Path $rootdir)) {
    Write-Host("Invalid docker provider root source dir : " + $rootdir + " ") -ForegroundColor Red
    exit
}

$publishdir = Join-Path -Path $rootdir -ChildPath "kubernetes\windows\omsagentwindows"
if ($true -eq (Test-Path -Path $publishdir)) {
    Write-Host("publish dir exist hence deleting: " + $publishdir + " ")
    Remove-Item -Path $publishdir  -Recurse -Force
}
Write-Host("creating publish dir exist: " + $publishdir + " ")
New-Item -Path $publishdir -ItemType "directory" -Force

$certreleasepublishpath = Join-Path  -Path $publishdir -ChildPath "certificategenerator.zip"

Write-Host("Compressing and copying the certificate generator release binaries ...")
Compress-Archive -Path  $certreleasebinpath -DestinationPath $certreleasepublishpath  -Force
Write-Host("Successfully copied compressed certificate generator release binaries") -ForegroundColor Green

# build  the shared object (.so) for out oms go plugin code
$outomsgoplugindir = Join-Path -Path $rootdir -ChildPath "source\code\go\src\plugins"
Write-Host("Building Out_OMS go plugin code...")
if ($false -eq (Test-Path -Path $outomsgoplugindir)) {
    Write-Host("Invalid Out oms go plugin code dir : " + $outomsgoplugindir + " ") -ForegroundColor Red
    exit
}
Set-Location -Path $outomsgoplugindir
Write-Host("getting latest go modules ...")
go get
Write-Host("successfyullt got latest go modules") -ForegroundColor Green

go build -ldflags "-X 'main.revision=$buildVersionString' -X 'main.builddate=$buildVersionDate'" -buildmode=c-shared -o out_oms.so .
Write-Host("Successfully build Out_OMS go plugin code") -ForegroundColor Green

Write-Host("copying out_oms.so file to : $publishdir")
Copy-Item -Path (Join-path -Path $outomsgoplugindir -ChildPath "out_oms.so")  -Destination $publishdir -Force
Write-Host("successfully copied out_oms.so file to : $publishdir") -ForegroundColor Green


$installerdir = Join-Path -Path $builddir -ChildPath "windows\installer"
Write-Host("copying installer files conf and scripts from :" + $installerdir + "  to  :" + $publishdir + " ...")
$exclude = @('*.cs','*.csproj')
Copy-Item  -Path $installerdir  -Destination $publishdir -Recurse -Force -Exclude $exclude
Write-Host("successfully copied installer files conf and scripts from :" + $installerdir + "  to  :" + $publishdir + " ") -ForegroundColor Green

Set-Location $currentdir