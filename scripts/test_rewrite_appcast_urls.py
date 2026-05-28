import subprocess
import textwrap
from pathlib import Path

SCRIPT = Path(__file__).parent / "rewrite_appcast_urls.py"


def run(input_xml: str, tmp_path: Path) -> str:
    p = tmp_path / "appcast.xml"
    p.write_text(input_xml)
    subprocess.run(
        ["python3", str(SCRIPT), str(p), "--owner", "oreillymedia", "--repo", "prtracker"],
        check=True,
    )
    return p.read_text()


def test_rewrites_single_enclosure_to_github_releases_url(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <enclosure url="PRTracker-0.1.1.zip"
                         sparkle:version="2"
                         sparkle:shortVersionString="0.1.1"
                         length="123"
                         type="application/octet-stream"
                         sparkle:edSignature="abc"/>
            </item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert "https://github.com/oreillymedia/prtracker/releases/download/v0.1.1/PRTracker-0.1.1.zip" in out
    assert 'url="PRTracker-0.1.1.zip"' not in out


def test_rewrites_url_with_existing_prefix(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item>
              <enclosure url="https://example.com/old/PRTracker-0.1.2.zip"
                         sparkle:version="3"
                         sparkle:shortVersionString="0.1.2"
                         length="456"
                         type="application/octet-stream"
                         sparkle:edSignature="def"/>
            </item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert "https://github.com/oreillymedia/prtracker/releases/download/v0.1.2/PRTracker-0.1.2.zip" in out
    assert "example.com" not in out


def test_rewrites_multiple_items(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item><enclosure url="PRTracker-0.1.1.zip" length="1" type="application/octet-stream" sparkle:edSignature="a"/></item>
            <item><enclosure url="PRTracker-0.1.2.zip" length="2" type="application/octet-stream" sparkle:edSignature="b"/></item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert "/v0.1.1/PRTracker-0.1.1.zip" in out
    assert "/v0.1.2/PRTracker-0.1.2.zip" in out


def test_preserves_eddsa_signature(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item><enclosure url="PRTracker-0.1.1.zip" length="1" type="application/octet-stream" sparkle:edSignature="THESIG"/></item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert 'sparkle:edSignature="THESIG"' in out


def test_unrecognized_filename_is_left_alone(tmp_path):
    input_xml = textwrap.dedent("""\
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
          <channel>
            <item><enclosure url="https://elsewhere.example/some-other-thing.zip" length="1" type="application/octet-stream" sparkle:edSignature="x"/></item>
          </channel>
        </rss>
    """)
    out = run(input_xml, tmp_path)
    assert "https://elsewhere.example/some-other-thing.zip" in out
