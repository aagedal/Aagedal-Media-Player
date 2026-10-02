#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Self-contained regressions for the independent Premiere xmeml comparator."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("premiere", Path(__file__).with_name("compare-premiere-marker-roundtrip.py"))
premiere = importlib.util.module_from_spec(spec)
spec.loader.exec_module(premiere)


def fixture(base=30, ntsc=True, df=True):
    rate = f"<rate><timebase>{base}</timebase><ntsc>{str(ntsc).upper()}</ntsc></rate>"
    tc = f"<timecode>{rate}<frame>{base * 58}</frame><displayformat>{'DF' if df else 'NDF'}</displayformat></timecode>"
    geometry = f"<samplecharacteristics>{rate}<width>160</width><height>90</height><pixelaspectratio>square</pixelaspectratio></samplecharacteristics>"
    return ET.fromstring(f"""<xmeml version="5"><project><children><sequence id="review">
<name>Review</name><duration>20000</duration>{rate}{tc}
<marker><name>QC 001</name><in>0</in><out>1</out><comment>æøå 日本語 &amp; &lt;picture&gt; &quot;quoted&quot;\tcolumn\nSecond line</comment></marker>
<marker><name>QC 002</name><in>1</in><out>2</out><comment>Adjacent</comment></marker>
<marker><name>QC 003–004 (2 findings)</name><in>60</in><out>63</out><comment>QC 003: A frames 60–62 (inclusive)\n\nQC 004: duplicate</comment></marker>
<marker><name>QC 005</name><in>19999</in><out>20000</out><comment>Final frame</comment></marker>
<media><video><format>{geometry}</format><track><clipitem id="source-a"><name>source-a.mov</name>
<duration>20000</duration>{rate}<start>0</start><end>20000</end><in>0</in><out>20000</out>
<file id="media-a"><name>source-a.mov</name><pathurl>file:///tmp/source-a.mov</pathurl>
{rate}<duration>20000</duration>{tc}<media><video>{geometry}</video></media></file>
</clipitem></track></video></media></sequence></children></project></xmeml>""")


class RoundTripTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.before = self.root / "original.xml"
        self.after = self.root / "returned.xml"

    def compare(self, mutate=None, **kwargs):
        original = fixture()
        ET.ElementTree(original).write(self.before, encoding="utf-8")
        returned = copy.deepcopy(original)
        if mutate:
            mutate(returned)
        ET.ElementTree(returned).write(self.after, encoding="utf-8")
        return premiere.compare(self.before, self.after, **kwargs)

    def test_exact_match_with_unicode_multiline_ranges_adjacent_and_final_frames(self):
        result = self.compare()
        self.assertEqual(result["status"], "exact-match")
        self.assertEqual(result["original"]["rate"], "30000/1001")
        self.assertEqual([m[:2] for m in result["original"]["markers"]], [(0, 1), (1, 1), (60, 3), (19999, 1)])
        self.assertIn('æøå 日本語 & <picture> "quoted"\tcolumn\nSecond line', result["original"]["markers"][0][3])
        self.assertFalse(result["mediaBytesCompared"])

    def test_retained_native_roundtrips_keep_recorded_differences_and_payloads(self):
        evidence = Path(__file__).resolve().parents[1] / "docs/evidence/premiere-native-roundtrip-20261001"
        for carrier, receipt in (("23976", "23976"), ("2997DF", "2997DF"),
                                 ("5994DF", "5994DF"), ("LiteralLF", "LiteralLF"),
                                 ("VisibleDelimiter", "VisibleDelimiter")):
            recorded = json.loads((evidence / f"{receipt}-comparison.json").read_text())
            result = premiere.compare(evidence / f"Aagedal-Review-{carrier}.xml",
                                      evidence / f"Aagedal-Review-{carrier}-Premiere-Roundtrip.xml")
            # The media is intentionally not retained. XML fixtures alone can
            # preserve observed differences but cannot re-establish byte proof.
            with self.subTest(carrier=carrier):
                self.assertEqual(result["status"], "differences")
                self.assertFalse(result["mediaBytesCompared"])
                self.assertEqual(result["checks"], {key: value for key, value in recorded["checks"].items()
                                                    if key != "sourceMediaBytes"})
                for side in ("original", "returned"):
                    self.assertEqual(json.loads(json.dumps(result[side])),
                                     {key: value for key, value in recorded[side].items() if key != "mediaSHA256"})

    def test_reordered_markers_and_xml_ids_are_not_marker_identity(self):
        def mutate(root):
            sequence = root.find(".//sequence")
            sequence.set("id", "native-generated")
            markers = sequence.findall("marker")
            for marker in markers:
                sequence.remove(marker)
            sequence.extend(reversed(markers))
        self.assertEqual(self.compare(mutate)["status"], "exact-match")

    def test_missing_added_moved_duration_and_changed_text_cannot_pass(self):
        for field in ("missing", "extra", "in", "out", "name", "comment"):
            def mutate(root):
                sequence = root.find(".//sequence")
                marker = sequence.find("marker")
                if field == "missing":
                    sequence.remove(marker)
                elif field == "extra":
                    sequence.append(copy.deepcopy(marker))
                else:
                    marker.find(field).text = {"in": "1", "out": "3", "name": "Changed", "comment": "Flattened"}[field]
                    if field == "in":
                        marker.find("out").text = "2"
            with self.subTest(field=field):
                self.assertEqual(self.compare(mutate)["status"], "differences")

    def test_undefined_point_out_compares_as_one_frame_but_retains_encoding(self):
        result = self.compare(lambda root: setattr(root.find(".//marker/out"), "text", "-1"))
        self.assertEqual(result["status"], "exact-match")
        self.assertEqual(result["returned"]["encodedMarkerOutFrames"][0], -1)

    def test_native_double_escaped_marker_linefeed_is_content_difference(self):
        # Observed in Premiere's 23.976 XML round trip on 2026-10-01:
        # app XML &#10;&#10; becomes native XML &amp;#10;&amp;#10;.
        # Decode XML once; recursively decoding would conceal changed text.
        original = fixture()
        returned = copy.deepcopy(original)
        comment = returned.findall(".//sequence/marker")[2].find("comment")
        comment.text = comment.text.replace("\n", "&#10;")
        ET.ElementTree(original).write(self.before, encoding="utf-8")
        self.before.write_bytes(self.before.read_bytes().replace(
            b"(inclusive)\n\nQC", b"(inclusive)&#10;&#10;QC"))
        ET.ElementTree(returned).write(self.after, encoding="utf-8")
        self.assertIn(b"&#10;&#10;", self.before.read_bytes())
        self.assertIn(b"&amp;#10;&amp;#10;", self.after.read_bytes())
        result = premiere.compare(self.before, self.after)
        self.assertEqual(result["status"], "differences")
        self.assertEqual([key for key, passed in result["checks"].items() if not passed],
                         ["exactMarkerContent"])
        self.assertIn("\n\n", result["original"]["markers"][2][3])
        self.assertIn("&#10;&#10;", result["returned"]["markers"][2][3])

    def test_changed_authored_whitespace_is_exact_content_difference(self):
        # References preserve CR separately from LF; comparing stripped or
        # normalized text would conceal real native whitespace loss.
        for before, after in (("  leading and trailing  ", "leading and trailing"),
                              ("tab\tcolumn", "tab column"),
                              ("CR\rline", "CR\nline"),
                              ("CRLF\r\nline", "CRLF\nline"),
                              ("blank\n\nline", "blank\nline"),
                              ("literal &#13;", "literal \r")):
            original = fixture()
            original.find(".//marker/comment").text = before
            returned = copy.deepcopy(original)
            returned.find(".//marker/comment").text = after
            for path, root in ((self.before, original), (self.after, returned)):
                path.write_bytes(ET.tostring(root, encoding="utf-8").replace(b"\r", b"&#13;"))
            with self.subTest(before=before, after=after):
                result = premiere.compare(self.before, self.after)
                self.assertEqual(result["status"], "differences")
                self.assertEqual(result["original"]["markers"][0][3], before)
                self.assertEqual(result["returned"]["markers"][0][3], after)
                self.assertEqual([key for key, passed in result["checks"].items() if not passed],
                                 ["exactMarkerContent"])

    def test_nested_scalar_content_cannot_be_silently_ignored(self):
        paths = (".//marker/comment", ".//marker/name", ".//marker/in", ".//marker/out",
                 ".//sequence/name", ".//sequence/duration", ".//sequence/rate/timebase",
                 ".//sequence/rate/ntsc", ".//sequence/timecode/frame",
                 ".//sequence/timecode/displayformat", ".//file/pathurl",
                 ".//format/samplecharacteristics/width",
                 ".//format/samplecharacteristics/pixelaspectratio")
        for path in paths:
            def mutate(root):
                child = ET.SubElement(root.find(path), "unexpected")
                child.text = "hidden native content"
                child.tail = "silently omitted tail"
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, "Nested content in scalar"):
                self.compare(mutate)
        for parent, field, value in ((".//sequence/timecode", "string", "00:00:58;00"),
                                     (".//clipitem", "pixelaspectratio", "square"),
                                     (".//clipitem", "fielddominance", "upper"),
                                     (".//clipitem", "enabled", "TRUE")):
            def mutate(root):
                node = ET.SubElement(root.find(parent), field)
                node.text = value
                ET.SubElement(node, "unexpected").text = "hidden"
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "Nested content in scalar"):
                self.compare(mutate)

    def test_empty_scalar_marker_comment_remains_supported(self):
        root = fixture()
        root.find(".//marker/comment").text = None
        ET.ElementTree(root).write(self.before)
        ET.ElementTree(root).write(self.after)
        result = premiere.compare(self.before, self.after)
        self.assertEqual(result["status"], "exact-match")
        self.assertEqual(result["original"]["markers"][0][3], "")

    def test_all_supported_exact_rates_and_drop_frame_modes(self):
        for base, ntsc, df, expected in ((24, True, False, "24000/1001"), (30, True, True, "30000/1001"),
                                         (60, True, True, "60000/1001"), (24, False, False, "24")):
            with self.subTest(rate=expected):
                ET.ElementTree(fixture(base, ntsc, df)).write(self.before)
                self.assertEqual(premiere.read_export(self.before)["rate"], expected)

    def test_explicit_default_timecode_field_and_source_match_omitted_defaults(self):
        def mutate(root):
            for tc in root.findall(".//timecode"):
                ET.SubElement(tc, "field").text = "0"
                ET.SubElement(tc, "source").text = "source"
        result = self.compare(mutate)
        self.assertEqual(result["status"], "exact-match")
        self.assertEqual(result["original"]["sequenceTimecode"], result["returned"]["sequenceTimecode"])
        self.assertEqual(result["original"]["sourceTimecode"], result["returned"]["sourceTimecode"])

    def test_nondefault_invalid_and_ambiguous_timecode_field_or_source_rejected(self):
        # Identical encoded frame numbers do not prove the same timecode clock
        # or field. Before this guard these changed carriers passed exact-match.
        for path in (".//sequence/timecode", ".//file/timecode"):
            for field, variants in (("field", (("1",), ("-1",), (None,), ("0", "0"), ("0", "1"))),
                                    ("source", (("aux1",), ("aux2",), ("sound",), ("SOURCE",),
                                                (None,), ("source", "source"), ("source", "aux1")))):
                for values in variants:
                    def mutate(root):
                        for value in values:
                            ET.SubElement(root.find(path), field).text = value
                    with self.subTest(path=path, field=field, values=values), self.assertRaises(ValueError):
                        self.compare(mutate)

    def test_nested_timecode_field_and_source_rejected(self):
        for path in (".//sequence/timecode", ".//file/timecode"):
            for field, value in (("field", "0"), ("source", "source")):
                def mutate(root):
                    node = ET.SubElement(root.find(path), field)
                    node.text = value
                    ET.SubElement(node, "unexpected").text = "hidden native content"
                with self.subTest(path=path, field=field), self.assertRaisesRegex(ValueError, "Nested content in scalar"):
                    self.compare(mutate)

    def test_changed_timecode_media_path_and_geometry_fail(self):
        mutations = (("sequenceTimecode", "./project/children/sequence/timecode/frame", "1741"),
                     ("sourceTimecode", ".//file/timecode/displayformat", "NDF"),
                     ("sourcePath", ".//file/pathurl", "file:///tmp/wrong.mov"),
                     ("sequenceGeometry", ".//format/samplecharacteristics/width", "1920"),
                     ("sourceGeometry", ".//file/media/video/samplecharacteristics/pixelaspectratio", "NTSC-CCIR601"))
        for check, path, value in mutations:
            with self.subTest(check=check):
                result = self.compare(lambda root: setattr(root.find(path), "text", value))
                self.assertEqual(result["status"], "differences")
                self.assertFalse(result["checks"][check])

    def test_timecode_strings_must_agree_with_encoded_frames(self):
        def label(root, value, source=False):
            tc = root.find(".//file/timecode" if source else "./project/children/sequence/timecode")
            ET.SubElement(tc, "string").text = value
        self.assertEqual(self.compare(lambda root: label(root, "00:00:58;00"))["status"], "exact-match")
        # Colon-delimited DF is also interpreted from displayformat, preserving
        # exact frame semantics rather than relying on punctuation alone.
        self.assertEqual(self.compare(lambda root: label(root, "00:00:58:00"))["status"], "exact-match")
        for value in ("00:00:58;01", "00:01:00;00", "00:60:00;00", "24:00:00;00", "00:00:58;30", "garbage", ""):
            for source in (False, True):
                with self.subTest(value=value, source=source), self.assertRaises(ValueError):
                    self.compare(lambda root: label(root, value, source))
        with self.assertRaises(ValueError):
            self.compare(lambda root: (label(root, "00:00:58;00"), label(root, "00:00:58;00")))

    def test_native_semicolon_separated_df_timecode_preserves_frame_semantics(self):
        # Premiere 26.5.1 returned this source/sequence label for frame 1798
        # in the native 29.97 DF minute-boundary fixture on 2026-10-01.
        original = fixture()
        for tc in original.findall(".//timecode"):
            tc.find("frame").text = "1798"
            ET.SubElement(tc, "string").text = "00:00:59;28"
        returned = copy.deepcopy(original)
        for tc in returned.findall(".//timecode"):
            tc.find("string").text = "00;00;59;28"
        ET.ElementTree(original).write(self.before)
        ET.ElementTree(returned).write(self.after)
        result = premiere.compare(self.before, self.after)
        self.assertEqual(result["status"], "exact-match")
        self.assertEqual(result["returned"]["sourceTimecode"], dict(frame=1798, displayFormat="DF"))
        for value in ("00;00:59;28", "00:00;59;28", "00;00;59:28", "00;00:59:28",
                      "00:00;59:28", "00;00;59;29", "00;01;00;00"):
            returned.find(".//sequence/timecode/string").text = value
            ET.ElementTree(returned).write(self.after)
            with self.subTest(value=value), self.assertRaises(ValueError):
                premiere.compare(self.before, self.after)
        returned.find(".//sequence/timecode/string").text = "00;00;59;28"
        returned.find(".//sequence/timecode/displayformat").text = "NDF"
        ET.ElementTree(returned).write(self.after)
        with self.assertRaisesRegex(ValueError, "delimiter contradict"):
            premiere.compare(self.before, self.after)

    def test_changed_sequence_source_and_clip_field_order_cannot_pass(self):
        for path, check in ((".//format/samplecharacteristics", "sequenceGeometry"),
                            (".//file/media/video/samplecharacteristics", "sourceGeometry"),
                            (".//clipitem", "clipFieldDominance")):
            def mutate(root):
                ET.SubElement(root.find(path), "fielddominance").text = "upper"
            with self.subTest(path=path):
                result = self.compare(mutate)
                self.assertEqual(result["status"], "differences")
                self.assertFalse(result["checks"][check])

    def test_known_field_order_retained_and_matching_clip_override_is_equivalent(self):
        for value in ("none", "upper", "lower", "odd", "even"):
            original = fixture()
            for sample in original.findall(".//samplecharacteristics"):
                ET.SubElement(sample, "fielddominance").text = value
            returned = copy.deepcopy(original)
            ET.SubElement(returned.find(".//clipitem"), "fielddominance").text = value
            ET.ElementTree(original).write(self.before)
            ET.ElementTree(returned).write(self.after)
            with self.subTest(value=value):
                result = premiere.compare(self.before, self.after)
                self.assertEqual(result["status"], "exact-match")
                self.assertEqual(result["original"]["sequenceGeometry"]["fieldDominance"], value)
                self.assertEqual(result["original"]["sourceGeometry"]["fieldDominance"], value)
                self.assertEqual(result["returned"]["clipFieldDominance"], value)
            returned.find(".//clipitem/fielddominance").text = "lower" if value == "upper" else "upper"
            ET.ElementTree(returned).write(self.after)
            self.assertFalse(premiere.compare(self.before, self.after)["checks"]["clipFieldDominance"])

    def test_invalid_or_ambiguous_field_order_rejected_at_every_scope(self):
        for path in (".//format/samplecharacteristics", ".//file/media/video/samplecharacteristics", ".//clipitem"):
            for values in ((None,), ("mixed",), ("UPPER",), ("upper", "upper"), ("upper", "lower")):
                def mutate(root):
                    for value in values:
                        ET.SubElement(root.find(path), "fielddominance").text = value
                with self.subTest(path=path, values=values), self.assertRaisesRegex(ValueError, "field dominance"):
                    self.compare(mutate)

    def test_drop_frame_strings_at_minute_and_ten_minute_boundaries(self):
        for base, frame, value in ((30, 1800, "00:01:00;02"), (30, 17982, "00:10:00;00"),
                                   (60, 3600, "00:01:00;04"), (60, 35964, "00:10:00;00")):
            for label in (value, value.replace(":", ";")):
                root = fixture(base, True, True)
                for tc in root.findall(".//timecode"):
                    tc.find("frame").text = str(frame)
                    ET.SubElement(tc, "string").text = label
                ET.ElementTree(root).write(self.before)
                with self.subTest(label=label, base=base):
                    self.assertEqual(premiere.read_export(self.before)["sequenceTimecode"]["frame"], frame)

    def test_short_relinked_media_and_absent_geometry_do_not_fake_source_duration(self):
        def mutate(root):
            root.find(".//sequence/duration").text = "20001"
            sequence_format = root.find(".//sequence/media/video/format")
            sequence_format.remove(sequence_format.find("samplecharacteristics"))
            media_video = root.find(".//file/media/video")
            media_video.remove(media_video.find("samplecharacteristics"))
        root = fixture()
        mutate(root)
        ET.ElementTree(root).write(self.before)
        ET.ElementTree(root).write(self.after)
        result = premiere.compare(self.before, self.after)
        self.assertEqual(result["status"], "exact-match")
        self.assertEqual(result["original"]["durationFrames"], 20001)
        self.assertEqual(result["original"]["sourceDurationFrames"], 20000)
        self.assertIsNone(result["original"]["sourceGeometry"])

    def test_native_file_reference_and_localhost_url_resolve(self):
        def mutate(root):
            clip = root.find(".//clipitem")
            media = clip.find("file")
            clip.remove(media)
            ET.SubElement(clip, "file", id="media-a")
            media.find("pathurl").text = "file://localhost/tmp/source-a.mov"
            root.append(media)
        self.assertEqual(self.compare(mutate)["status"], "exact-match")

    def test_explicit_primary_video_source_track_matches_implicit_carrier(self):
        for include_index in (False, True):
            def mutate(root):
                selector = ET.SubElement(root.find(".//clipitem"), "sourcetrack")
                ET.SubElement(selector, "mediatype").text = "video"
                if include_index:
                    ET.SubElement(selector, "trackindex").text = "1"
            with self.subTest(include_index=include_index):
                self.assertEqual(self.compare(mutate)["status"], "exact-match")

    def test_changed_invalid_or_ambiguous_source_track_cannot_pass_same_file(self):
        # Source path, clip placement and marker content all stay unchanged.
        # A different connected track must not masquerade as the same source A.
        for media_types, indices, copies in ((("video",), ("2",), 1),
                                              (("video",), ("0",), 1),
                                              (("video",), ("-1",), 1),
                                              (("video",), (None,), 1),
                                              (("video",), ("1", "1"), 1),
                                              (("video",), ("1", "2"), 1),
                                              (("audio",), ("1",), 1),
                                              (("VIDEO",), ("1",), 1),
                                              ((None,), ("1",), 1),
                                              ((), ("1",), 1),
                                              (("video", "video"), ("1",), 1),
                                              (("video",), ("1",), 2)):
            def mutate(root):
                for _ in range(copies):
                    selector = ET.SubElement(root.find(".//clipitem"), "sourcetrack")
                    for value in media_types:
                        ET.SubElement(selector, "mediatype").text = value
                    for value in indices:
                        ET.SubElement(selector, "trackindex").text = value
            with self.subTest(media_types=media_types, indices=indices, copies=copies), self.assertRaises(ValueError):
                self.compare(mutate)

    def test_nested_source_track_scalar_fields_rejected(self):
        for field in ("mediatype", "trackindex"):
            def mutate(root):
                selector = ET.SubElement(root.find(".//clipitem"), "sourcetrack")
                ET.SubElement(selector, "mediatype").text = "video"
                ET.SubElement(selector, "trackindex").text = "1"
                ET.SubElement(selector.find(field), "unexpected").text = "hidden native content"
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "Nested content in scalar"):
                self.compare(mutate)

    def test_still_frame_source_cannot_pass_unchanged_path_and_frame_placement(self):
        for path in (".//clipitem", ".//file/media/video"):
            for values in (("TRUE",), ("false",), (None,), ("FALSE", "FALSE"), ("FALSE", "TRUE")):
                def mutate(root):
                    for value in values:
                        ET.SubElement(root.find(path), "stillframe").text = value
                with self.subTest(path=path, values=values), self.assertRaisesRegex(ValueError, "must not be a still frame"):
                    self.compare(mutate)
        def moving(root):
            for path in (".//clipitem", ".//file/media/video"):
                ET.SubElement(root.find(path), "stillframe").text = "FALSE"
        self.assertEqual(self.compare(moving)["status"], "exact-match")

    def test_source_frame_offsets_and_multiclip_cannot_pass_unchanged_placement(self):
        for field in ("stillframeoffset", "mixedratesoffset", "mediadelay"):
            for values in (("1",), ("-1",), (None,), ("0", "0"), ("0", "1")):
                def mutate(root):
                    for value in values:
                        ET.SubElement(root.find(".//clipitem"), field).text = value
                with self.subTest(field=field, values=values), self.assertRaises(ValueError):
                    self.compare(mutate)
        with self.assertRaisesRegex(ValueError, "multiclip"):
            self.compare(lambda root: ET.SubElement(root.find(".//clipitem"), "multiclip"))

    def test_subframe_source_slips_cannot_pass_unchanged_integer_placement(self):
        for values in (("0.5",), ("-0.0001",), ("1",), (None,), ("garbage",), ("0", "0")):
            def mutate(root):
                for value in values:
                    ET.SubElement(root.find(".//clipitem"), "subframeoffset").text = value
            with self.subTest(values=values), self.assertRaises(ValueError):
                self.compare(mutate)

    def test_explicit_zero_source_offsets_match_continuous_untrimmed_carrier(self):
        for subframe in ("0", "0.0", "-0.000"):
            def mutate(root):
                clip = root.find(".//clipitem")
                for field in ("stillframeoffset", "mixedratesoffset", "mediadelay"):
                    ET.SubElement(clip, field).text = "0"
                ET.SubElement(clip, "subframeoffset").text = subframe
            with self.subTest(subframe=subframe):
                self.assertEqual(self.compare(mutate)["status"], "exact-match")

    def test_native_premiere_tick_endpoints_must_match_frame_endpoints_exactly(self):
        # Native retained receipts encode pproTicksIn/Out in addition to frames.
        # Test integer, fractional and DF clocks without rounding through float.
        for base, ntsc, df in ((24, False, False), (24, True, False), (30, True, True), (60, True, True)):
            original = fixture(base, ntsc, df)
            returned = copy.deepcopy(original)
            fps = premiere.rate(returned.find(".//clipitem"))
            expected = premiere.Fraction(20000 * 254016000000, fps)
            self.assertEqual(expected.denominator, 1)
            ET.SubElement(returned.find(".//clipitem"), "pproTicksIn").text = "0"
            ET.SubElement(returned.find(".//clipitem"), "pproTicksOut").text = str(expected.numerator)
            ET.ElementTree(original).write(self.before)
            ET.ElementTree(returned).write(self.after)
            with self.subTest(base=base, ntsc=ntsc):
                self.assertEqual(premiere.compare(self.before, self.after)["status"], "exact-match")
            for field in ("pproTicksIn", "pproTicksOut"):
                node = returned.find(f".//clipitem/{field}")
                old_value = node.text
                for value in (str(int(old_value) + 1), "-1", "1.5", None):
                    node.text = value
                    ET.ElementTree(returned).write(self.after)
                    with self.subTest(base=base, field=field, value=value), self.assertRaises(ValueError):
                        premiere.compare(self.before, self.after)
                node.text = old_value
                duplicate = ET.SubElement(returned.find(".//clipitem"), field)
                duplicate.text = old_value
                ET.ElementTree(returned).write(self.after)
                with self.subTest(base=base, field=field), self.assertRaisesRegex(ValueError, "ambiguous Premiere"):
                    premiere.compare(self.before, self.after)
                returned.find(".//clipitem").remove(duplicate)

    def test_nested_source_timing_scalar_content_rejected(self):
        for field, value in (("stillframe", "FALSE"), ("stillframeoffset", "0"), ("mixedratesoffset", "0"),
                             ("mediadelay", "0"), ("subframeoffset", "0.0"), ("pproTicksIn", "0")):
            def mutate(root):
                node = ET.SubElement(root.find(".//clipitem"), field)
                node.text = value
                ET.SubElement(node, "unexpected").text = "concealed source change"
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "Nested content in scalar"):
                self.compare(mutate)

    def test_changed_clip_pixel_aspect_cannot_pass_unchanged_file_and_sequence(self):
        result = self.compare(lambda root: setattr(
            ET.SubElement(root.find(".//clipitem"), "pixelaspectratio"), "text", "NTSC-601"))
        self.assertEqual(result["status"], "differences")
        self.assertTrue(result["checks"]["sequenceGeometry"])
        self.assertTrue(result["checks"]["sourceGeometry"])
        self.assertFalse(result["checks"]["clipPixelAspect"])
        self.assertEqual(result["original"]["clipPixelAspect"], "square")
        self.assertEqual(result["returned"]["clipPixelAspect"], "NTSC-601")

    def test_matching_clip_pixel_aspect_override_uses_source_not_sequence(self):
        original = fixture()
        original.find(".//file/media/video/samplecharacteristics/pixelaspectratio").text = "PAL-601"
        returned = copy.deepcopy(original)
        ET.SubElement(returned.find(".//clipitem"), "pixelaspectratio").text = "PAL-601"
        ET.ElementTree(original).write(self.before)
        ET.ElementTree(returned).write(self.after)
        result = premiere.compare(self.before, self.after)
        self.assertEqual(result["status"], "exact-match")
        self.assertEqual(result["original"]["clipPixelAspect"], "PAL-601")
        self.assertEqual(result["returned"]["clipPixelAspect"], "PAL-601")
        returned.find(".//clipitem/pixelaspectratio").text = "square"
        ET.ElementTree(returned).write(self.after)
        self.assertFalse(premiere.compare(self.before, self.after)["checks"]["clipPixelAspect"])

    def test_empty_and_ambiguous_clip_pixel_aspect_overrides_rejected(self):
        for values in ((None,), ("",), (" ",), ("square", "square"), ("square", "NTSC-601")):
            def mutate(root):
                for value in values:
                    ET.SubElement(root.find(".//clipitem"), "pixelaspectratio").text = value
            with self.subTest(values=values), self.assertRaisesRegex(ValueError, "pixel aspect"):
                self.compare(mutate)

    def test_explicit_enabled_sequence_track_and_clip_match_default_enabled(self):
        def mutate(root):
            for path in (".//sequence", ".//sequence/media/video/track", ".//clipitem"):
                ET.SubElement(root.find(path), "enabled").text = "TRUE"
        self.assertEqual(self.compare(mutate)["status"], "exact-match")

    def test_disabled_invalid_and_duplicate_enabled_values_rejected(self):
        for path in (".//sequence", ".//sequence/media/video/track", ".//clipitem"):
            for values in (("FALSE",), ("true",), ("MAYBE",), (None,), ("TRUE", "TRUE"), ("TRUE", "FALSE")):
                def mutate(root):
                    for value in values:
                        ET.SubElement(root.find(path), "enabled").text = value
                with self.subTest(path=path, values=values), self.assertRaisesRegex(ValueError, "must be enabled"):
                    self.compare(mutate)

    def test_additional_generator_on_source_a_video_track_rejected(self):
        def mutate(root):
            generator = ET.SubElement(root.find(".//sequence/media/video/track"), "generatoritem")
            ET.SubElement(generator, "name").text = "Unexpected title"
            ET.SubElement(generator, "start").text = "0"
            ET.SubElement(generator, "end").text = "20000"
        with self.assertRaisesRegex(ValueError, "exactly one video track"):
            self.compare(mutate)

    def test_returned_multiple_sequences_require_unique_explicit_selection(self):
        def mutate(root):
            children = root.find("project/children")
            second = copy.deepcopy(children.find("sequence"))
            second.find("name").text = "Other sequence"
            children.append(second)
        with self.assertRaises(ValueError):
            self.compare(mutate)
        self.assertEqual(self.compare(mutate, returned_sequence_name="Review")["status"], "exact-match")
        with self.assertRaises(ValueError):
            self.compare(mutate, returned_sequence_name="Missing")
        with self.assertRaises(ValueError):
            self.compare(lambda root: root.find("project/children").append(copy.deepcopy(root.find(".//sequence"))),
                         returned_sequence_name="Review")

    def test_malformed_trimmed_nested_and_wrong_scope_inputs_rejected(self):
        mutations = ((".//marker/in", "-1"), (".//marker/out", "0"), (".//marker/out", "20001"),
                     (".//clipitem/start", "1"), (".//clipitem/in", "1"), (".//file/duration", "1"),
                     (".//sequence/rate/ntsc", "MAYBE"), (".//file/pathurl", "https://example.com/a.mov"))
        for path, value in mutations:
            with self.subTest(path=path, value=value), self.assertRaises(ValueError):
                self.compare(lambda root: setattr(root.find(path), "text", value))
        with self.assertRaises(ValueError):
            self.compare(lambda root: root.find(".//clipitem").append(ET.Element("marker")))
        with self.assertRaises(ValueError):
            self.compare(lambda root: root.find(".//clipitem").append(ET.Element("filter")))

    def test_external_entities_and_fcpxml_rejected(self):
        for data in (b'<!DOCTYPE xmeml SYSTEM "remote.dtd"><xmeml version="5"/>',
                     b'<!DOCTYPE xmeml [<!ENTITY evil "oops">]><xmeml version="5"/>', b'<fcpxml version="1.10"/>'):
            self.before.write_bytes(data)
            with self.subTest(data=data), self.assertRaises(ValueError):
                premiere.read_export(self.before)

    def test_encoded_dtd_and_entity_declarations_rejected_before_parsing(self):
        document = ET.tostring(fixture(), encoding="unicode")
        declarations = ('<!DOCTYPE xmeml SYSTEM "remote.dtd">',
                        '<!DOCTYPE xmeml PUBLIC "remote" "remote.dtd">',
                        '<!DOCTYPE xmeml [<!ENTITY title "QC 001">]>')
        for encoding in ("utf-8", "utf-16", "utf-16-le", "utf-16-be", "utf-32", "utf-32-le", "utf-32-be"):
            for declaration in declarations:
                xml = document.replace("QC 001", "&title;") if "<!ENTITY" in declaration else document
                self.before.write_bytes((f'<?xml version="1.0" encoding="{encoding}"?>'
                                         + declaration + xml).encode(encoding))
                with self.subTest(encoding=encoding, declaration=declaration), self.assertRaisesRegex(
                        ValueError, "External DTDs and entity declarations are unsupported"):
                    premiere.read_export(self.before)

    def test_plain_doctype_and_utf16_unicode_document_remain_supported(self):
        document = ET.tostring(fixture(), encoding="unicode")
        self.before.write_bytes(document.encode("utf-8"))
        self.after.write_bytes(('<?xml version="1.0" encoding="UTF-16"?><!DOCTYPE xmeml>'
                                + document).encode("utf-16"))
        self.assertEqual(premiere.compare(self.before, self.after)["status"], "exact-match")

    def test_optional_media_bytes_and_report_no_overwrite(self):
        media = self.root / "source a.mov"
        media.write_bytes(b"generated permission-cleared fixture bytes")
        root = fixture()
        root.find(".//file/pathurl").text = media.as_uri()
        ET.ElementTree(root).write(self.before)
        ET.ElementTree(root).write(self.after)
        result = premiere.compare(self.before, self.after, verify_media=True)
        self.assertTrue(result["checks"]["sourceMediaBytes"])
        self.assertEqual(result["original"]["mediaSHA256"], premiere.digest(media))
        report = self.root / "report.json"
        command = [sys.executable, str(Path(premiere.__file__)), str(self.before), str(self.after), "--output", str(report)]
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        self.assertEqual(json.loads(report.read_text())["status"], "exact-match")
        previous = report.read_bytes()
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 2)
        self.assertEqual(report.read_bytes(), previous)
        media.unlink()
        with self.assertRaises(OSError):
            premiere.compare(self.before, self.after, verify_media=True)

    def capture_media_baseline(self):
        media = self.root / "source a.mov"
        media.write_bytes(b"original permission-cleared fixture")
        original = fixture()
        original.find(".//file/pathurl").text = media.as_uri()
        ET.ElementTree(original).write(self.before)
        ET.ElementTree(original).write(self.after)
        report = self.root / "baseline.json"
        report.write_text(json.dumps(premiere.compare(self.before, self.before, verify_media=True)))
        return media, report

    def test_preimport_baseline_detects_media_replaced_at_unchanged_source_path(self):
        media, baseline = self.capture_media_baseline()
        previous_receipt = baseline.read_bytes()
        result = premiere.compare(self.before, self.after, baseline_report=baseline)
        self.assertEqual(result["status"], "exact-match")
        self.assertTrue(result["mediaBytesCompared"])
        self.assertTrue(result["checks"]["sourceMediaMatchesBaseline"])
        expected_hash = result["mediaBaseline"]["mediaSHA256"]
        # Both XMLs reference the same pathname. Replacing bytes in place after
        # import used to pass because post-only verification read it twice.
        media.write_bytes(b"replaced permission-cleared fixture")
        self.assertEqual(premiere.compare(self.before, self.after, verify_media=True)["status"], "exact-match")
        result = premiere.compare(self.before, self.after, baseline_report=baseline)
        self.assertEqual(result["status"], "differences")
        self.assertTrue(result["checks"]["sourceMediaBytes"])
        self.assertEqual([key for key, passed in result["checks"].items() if not passed],
                         ["sourceMediaMatchesBaseline"])
        self.assertEqual(result["mediaBaseline"]["mediaSHA256"], expected_hash)
        self.assertNotEqual(result["returned"]["mediaSHA256"], expected_hash)
        self.assertEqual(baseline.read_bytes(), previous_receipt)

    def test_baseline_requires_exact_original_xml_hash_and_source_path(self):
        media, baseline = self.capture_media_baseline()
        captured = json.loads(baseline.read_text())
        for field, value in (("sha256", "0" * 64), ("sourcePath", str(self.root / "other.mov"))):
            report = copy.deepcopy(captured)
            report["original"][field] = value
            baseline.write_text(json.dumps(report))
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "does not match"):
                premiere.compare(self.before, self.after, baseline_report=baseline)
        baseline.write_text(json.dumps(captured))
        original = ET.parse(self.before)
        original.find(".//sequence/name").text = "Edited original"
        original.write(self.before)
        # The receipt cannot be reused for an edited XML even if the source
        # pathname, frame timing and file bytes are all still identical.
        with self.assertRaisesRegex(ValueError, "original XML SHA-256"):
            premiere.compare(self.before, self.after, baseline_report=baseline)

    def test_baseline_rejects_missing_invalid_or_unverified_byte_receipts(self):
        media, baseline = self.capture_media_baseline()
        captured = json.loads(baseline.read_text())
        for field, value in (("status", "invalid"), ("mediaBytesCompared", False),
                             ("checks", {"sourceMediaBytes": False}), ("original", None)):
            report = copy.deepcopy(captured)
            report[field] = value
            baseline.write_text(json.dumps(report))
            with self.subTest(field=field), self.assertRaisesRegex(ValueError, "byte receipt"):
                premiere.compare(self.before, self.after, baseline_report=baseline)
        for checksum in (None, "", "0" * 63, "z" * 64, "A" * 64, 123):
            report = copy.deepcopy(captured)
            report["original"]["mediaSHA256"] = checksum
            baseline.write_text(json.dumps(report))
            with self.subTest(checksum=checksum), self.assertRaisesRegex(ValueError, "valid original media SHA-256"):
                premiere.compare(self.before, self.after, baseline_report=baseline)
        for contents in ("null", "[]", "{}", "not JSON"):
            baseline.write_text(contents)
            with self.subTest(contents=contents), self.assertRaises(ValueError):
                premiere.compare(self.before, self.after, baseline_report=baseline)

    def test_baseline_cli_capture_compare_mutation_and_missing_media_exit_codes(self):
        media, baseline = self.capture_media_baseline()
        baseline.unlink()
        command = [sys.executable, str(Path(premiere.__file__)), str(self.before), str(self.before),
                   "--verify-media", "--output", str(baseline)]
        self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
        compare_command = [sys.executable, str(Path(premiere.__file__)), str(self.before), str(self.after),
                           "--baseline-report", str(baseline)]
        self.assertEqual(subprocess.run(compare_command, capture_output=True).returncode, 0)
        media.write_bytes(b"changed media still at the same path")
        completed = subprocess.run(compare_command, capture_output=True)
        self.assertEqual(completed.returncode, 1)
        self.assertFalse(json.loads(completed.stdout)["checks"]["sourceMediaMatchesBaseline"])
        media.unlink()
        completed = subprocess.run(compare_command, capture_output=True)
        self.assertEqual(completed.returncode, 2)
        self.assertEqual(json.loads(completed.stdout)["status"], "invalid")


if __name__ == "__main__":
    unittest.main()
