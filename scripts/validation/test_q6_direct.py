import pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
class Q6DirectShader(unittest.TestCase):
    def test_specialization_preserves_partial_block_guard_and_math(self):
        with tempfile.TemporaryDirectory() as output:
            subprocess.run(['python3',str(ROOT/'scripts/android/prepare-q6-direct.py'),str(ROOT),output],check=True)
            text=(pathlib.Path(output)/'mul_mat_vec_q6_k.comp').read_text()
            self.assertIn('constant_id = 3) const bool DIRECT_SCALES = false',text)
            self.assertIn('if (i >= num_blocks_per_row)\n                continue;',text)
            self.assertIn('if (all_threads && !DIRECT_SCALES)',text)
            self.assertIn('scales[s_offset + 2*sc]',text)
            self.assertIn('fma(sum[0], scales[0], fma(sum[1], scales[1]',text)
    def test_source_drift_fails_closed(self):
        with tempfile.TemporaryDirectory() as temp:
            root=pathlib.Path(temp)
            source=root/'Dependencies/vendor/llama.cpp/ggml/src/ggml-vulkan/vulkan-shaders'
            source.mkdir(parents=True)
            (source/'mul_mat_vec_q6_k.comp').write_text('upstream changed')
            result=subprocess.run(['python3',str(ROOT/'scripts/android/prepare-q6-direct.py'),str(root),str(root/'out')],capture_output=True)
            self.assertNotEqual(result.returncode,0)
            self.assertIn(b'Pinned Q6 shader changed',result.stderr)
