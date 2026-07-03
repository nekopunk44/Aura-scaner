import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img_lib;

/// Генерирует .pptx (Office Open XML) из списка изображений: одна страница
/// скана = один слайд 16:9, картинка вписана по центру с сохранением
/// пропорций. Пакетов для записи pptx в Dart нет, но формат — это ZIP с
/// XML-частями, поэтому собираем архив вручную через `archive`.
class PptxBuilder {
  // Слайд 16:9 в EMU (1 см = 360000 EMU).
  static const int _slideW = 12192000;
  static const int _slideH = 6858000;

  /// Собирает pptx и пишет его в [outputPath]. [imagePaths] — JPEG/PNG-файлы.
  static Future<File> build({
    required List<String> imagePaths,
    required String outputPath,
    String title = 'Aura Scanner',
  }) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError('Нет изображений для презентации');
    }

    final archive = Archive();
    void addXml(String path, String xml) {
      final bytes = utf8Bytes(xml);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    final n = imagePaths.length;

    // --- [Content_Types].xml -------------------------------------------
    final slideOverrides = StringBuffer();
    for (var i = 1; i <= n; i++) {
      slideOverrides.write(
        '<Override PartName="/ppt/slides/slide$i.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
      );
    }
    addXml('[Content_Types].xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="jpeg" ContentType="image/jpeg"/>
<Default Extension="jpg" ContentType="image/jpeg"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>
<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>
<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>
<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
$slideOverrides
</Types>''');

    // --- _rels/.rels -----------------------------------------------------
    addXml('_rels/.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>
</Relationships>''');

    // --- ppt/presentation.xml -------------------------------------------
    final sldIdLst = StringBuffer();
    final presRels = StringBuffer();
    presRels.write(
      '<Relationship Id="rIdMaster" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" '
      'Target="slideMasters/slideMaster1.xml"/>',
    );
    for (var i = 1; i <= n; i++) {
      sldIdLst.write('<p:sldId id="${255 + i}" r:id="rIdSlide$i"/>');
      presRels.write(
        '<Relationship Id="rIdSlide$i" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
        'Target="slides/slide$i.xml"/>',
      );
    }
    addXml('ppt/presentation.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rIdMaster"/></p:sldMasterIdLst>
<p:sldIdLst>$sldIdLst</p:sldIdLst>
<p:sldSz cx="$_slideW" cy="$_slideH"/>
<p:notesSz cx="$_slideH" cy="$_slideW"/>
</p:presentation>''');

    addXml('ppt/_rels/presentation.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
$presRels
</Relationships>''');

    // --- slideMaster / slideLayout / theme --------------------------------
    addXml('ppt/slideMasters/slideMaster1.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
</p:spTree></p:cSld>
<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>
<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
</p:sldMaster>''');

    addXml('ppt/slideMasters/_rels/slideMaster1.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>
</Relationships>''');

    addXml('ppt/slideLayouts/slideLayout1.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank">
<p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
</p:spTree></p:cSld>
<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sldLayout>''');

    addXml('ppt/slideLayouts/_rels/slideLayout1.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>
</Relationships>''');

    addXml('ppt/theme/theme1.xml', _minimalTheme);

    // --- Слайды и картинки -------------------------------------------------
    for (var i = 1; i <= n; i++) {
      final srcPath = imagePaths[i - 1];
      final bytes = await File(srcPath).readAsBytes();

      // Размер картинки для вписывания в слайд.
      int w = 1000, h = 1414;
      final decoded = img_lib.decodeImage(bytes);
      if (decoded != null) {
        w = decoded.width;
        h = decoded.height;
      }
      final scale = (_slideW / w) < (_slideH / h)
          ? (_slideW / w)
          : (_slideH / h);
      final cx = (w * scale).round();
      final cy = (h * scale).round();
      final offX = ((_slideW - cx) / 2).round();
      final offY = ((_slideH - cy) / 2).round();

      final ext = srcPath.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
      archive.addFile(
        ArchiveFile('ppt/media/image$i.$ext', bytes.length, bytes),
      );

      addXml('ppt/slides/slide$i.xml', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
<p:cSld><p:spTree>
<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>
<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>
<p:pic>
<p:nvPicPr><p:cNvPr id="2" name="Scan $i"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>
<p:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>
<p:spPr><a:xfrm><a:off x="$offX" y="$offY"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>
<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>
</p:pic>
</p:spTree></p:cSld>
<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
</p:sld>''');

      addXml('ppt/slides/_rels/slide$i.xml.rels', '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image$i.$ext"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>
</Relationships>''');
    }

    final zipBytes = ZipEncoder().encode(archive);
    final out = File(outputPath);
    await out.writeAsBytes(zipBytes);
    return out;
  }

  static Uint8List utf8Bytes(String s) =>
      Uint8List.fromList(utf8.encode(s.trim()));

  /// Минимальная валидная тема (обязательна для PowerPoint).
  static const String _minimalTheme = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Aura">
<a:themeElements>
<a:clrScheme name="Aura">
<a:dk1><a:sysClr val="windowText" lastClr="000000"/></a:dk1>
<a:lt1><a:sysClr val="window" lastClr="FFFFFF"/></a:lt1>
<a:dk2><a:srgbClr val="1A1A2E"/></a:dk2>
<a:lt2><a:srgbClr val="F2F6FC"/></a:lt2>
<a:accent1><a:srgbClr val="2CA5E0"/></a:accent1>
<a:accent2><a:srgbClr val="26C060"/></a:accent2>
<a:accent3><a:srgbClr val="FFC107"/></a:accent3>
<a:accent4><a:srgbClr val="E74C3C"/></a:accent4>
<a:accent5><a:srgbClr val="9B59B6"/></a:accent5>
<a:accent6><a:srgbClr val="34495E"/></a:accent6>
<a:hlink><a:srgbClr val="2CA5E0"/></a:hlink>
<a:folHlink><a:srgbClr val="9B59B6"/></a:folHlink>
</a:clrScheme>
<a:fontScheme name="Aura">
<a:majorFont><a:latin typeface="Calibri Light"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont>
<a:minorFont><a:latin typeface="Calibri"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont>
</a:fontScheme>
<a:fmtScheme name="Aura">
<a:fillStyleLst>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
</a:fillStyleLst>
<a:lnStyleLst>
<a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
<a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
<a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln>
</a:lnStyleLst>
<a:effectStyleLst>
<a:effectStyle><a:effectLst/></a:effectStyle>
<a:effectStyle><a:effectLst/></a:effectStyle>
<a:effectStyle><a:effectLst/></a:effectStyle>
</a:effectStyleLst>
<a:bgFillStyleLst>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>
</a:bgFillStyleLst>
</a:fmtScheme>
</a:themeElements>
</a:theme>''';
}
