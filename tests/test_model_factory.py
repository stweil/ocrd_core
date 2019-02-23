from tests.base import TestCase, main, assets

from ocrd_utils import MIMETYPE_PAGE
from ocrd_models import OcrdFile
from ocrd_modelfactory import (
    exif_from_filename,
    page_from_file
)

SAMPLE_IMG = assets.path_to('kant_aufklaerung_1784/data/OCR-D-IMG/INPUT_0017')
SAMPLE_PAGE = assets.path_to('kant_aufklaerung_1784/data/OCR-D-GT-PAGE/PAGE_0017_PAGE')

class TestModelFactory(TestCase):

    def test_exif_from_filename(self):
        exif_from_filename(SAMPLE_IMG)
        with self.assertRaisesRegex(Exception, "Must pass 'image_filename' to 'exif_from_filename'"):
            exif_from_filename(None)

    def test_page_from_image(self):
        exif_from_filename(SAMPLE_IMG)
        with self.assertRaisesRegex(Exception, "Must pass 'image_filename' to 'exif_from_filename'"):
            exif_from_filename(None)

    def test_page_from_file(self):
        f = OcrdFile(None, mimetype='image/tiff', local_filename=SAMPLE_IMG)
        self.assertEqual(f.mimetype, 'image/tiff')
        p = page_from_file(f)
        self.assertEqual(p.get_Page().imageWidth, 1457)

    def test_page_from_file_page(self):
        f = OcrdFile(None, mimetype=MIMETYPE_PAGE, local_filename=SAMPLE_PAGE)
        p = page_from_file(f)
        self.assertEqual(p.get_Page().imageWidth, 1457)

    def test_page_from_file_no_local_filename(self):
        with self.assertRaisesRegex(Exception, "input_file must have 'local_filename' property"):
            page_from_file(OcrdFile(None, mimetype='image/tiff'))

    def test_page_from_file_unsupported_mimetype(self):
        with self.assertRaisesRegex(Exception, "Unsupported mimetype"):
            page_from_file(OcrdFile(None, mimetype='foo/bar'))

if __name__ == '__main__':
    main()
