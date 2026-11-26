param(
  [Parameter(Mandatory = $true)][string]$Pdf,
  [Parameter(Mandatory = $true)][string]$Carpeta,
  [int]$Ancho = 1600
)
# Pasa cada hoja de un PDF a PNG con el lector de PDF de Windows (Windows.Data.Pdf).
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Storage.StorageFile, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Storage.StorageFolder, Windows.Storage, ContentType = WindowsRuntime]
$null = [Windows.Data.Pdf.PdfDocument, Windows.Data.Pdf, ContentType = WindowsRuntime]
$null = [Windows.Data.Pdf.PdfPageRenderOptions, Windows.Data.Pdf, ContentType = WindowsRuntime]

$asTaskGen = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$asTaskAccion = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]

function Esperar($op, [Type]$tipo) {
  $t = $asTaskGen.MakeGenericMethod($tipo).Invoke($null, @($op))
  $t.Wait(-1) | Out-Null
  $t.Result
}
function EsperarAccion($op) {
  $t = $asTaskAccion.Invoke($null, @($op))
  $t.Wait(-1) | Out-Null
}

New-Item -ItemType Directory -Force $Carpeta | Out-Null
$archivo = Esperar ([Windows.Storage.StorageFile]::GetFileFromPathAsync($Pdf)) ([Windows.Storage.StorageFile])
$doc = Esperar ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($archivo)) ([Windows.Data.Pdf.PdfDocument])
$destino = Esperar ([Windows.Storage.StorageFolder]::GetFolderFromPathAsync($Carpeta)) ([Windows.Storage.StorageFolder])
$base = [System.IO.Path]::GetFileNameWithoutExtension($Pdf)
for ($i = 0; $i -lt $doc.PageCount; $i++) {
  $hoja = $doc.GetPage($i)
  $nombre = "{0}_hoja{1}.png" -f $base, ($i + 1)
  $salida = Esperar ($destino.CreateFileAsync($nombre, [Windows.Storage.CreationCollisionOption]::ReplaceExisting)) ([Windows.Storage.StorageFile])
  $flujo = Esperar ($salida.OpenAsync([Windows.Storage.FileAccessMode]::ReadWrite)) ([Windows.Storage.Streams.IRandomAccessStream])
  $opciones = New-Object Windows.Data.Pdf.PdfPageRenderOptions
  $opciones.DestinationWidth = $Ancho
  EsperarAccion ($hoja.RenderToStreamAsync($flujo, $opciones))
  $flujo.Dispose()
  $hoja.Dispose()
  Write-Output (Join-Path $Carpeta $nombre)
}
