"""Read-only CausalNet architecture/weight smoke check. No camera or training.
Synthetic input is only a shape/finite-value check, not an accuracy evaluation.
"""
import argparse
import hashlib
import importlib.util
import json
import time
import sys
sys.dont_write_bytecode = True
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--model-dir', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
import torch

torch.set_num_threads(2)
root = args.model_dir.resolve()
spec = importlib.util.spec_from_file_location('causalnet_models', root / 'Models.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
model = module.CausalNet(image_size=28, patch_size=7, dim=256, heads=3,
    num_hierarchies=3, block_repeats=(3,3,9), num_classes=3, gamma=0.5)
weights = sorted((root/'best_weights').glob('*.pth'))
report = {'torch':torch.__version__, 'cuda_available':torch.cuda.is_available(),
    'parameter_count':sum(p.numel() for p in model.parameters()),
    'weight_files':[{'name':p.name,'bytes':p.stat().st_size} for p in weights],
    'limitations':['Synthetic input only; not dataset accuracy.',
        'No continuous event spotting or raw camera preprocessing available.',
        'No Parkinson population validation or Android deployment benchmark.']}
weight = weights[0]
t0 = time.perf_counter()
state = torch.load(weight, map_location='cpu', weights_only=True, mmap=True)
depths = tuple(max(int(k.split('.')[4]) for k in state if k.startswith(f'layers.{level}.0.layers.'))+1 for level in range(3))
gammas = {k: -float(v[3,0]) for k,v in state.items() if k.endswith('P_matrix')}
gamma = next(iter(gammas.values()))
report['gamma_from_saved_position_matrices'] = gammas
report['inferred_gamma'] = gamma
report['eval_script_depths']=[3,3,9]
report['inferred_weight_depths']=list(depths)
report['architecture_matches_eval_script']=depths==(3,3,9)
if depths!=(3,3,9):
    del model
    model=module.CausalNet(image_size=28,patch_size=7,dim=256,heads=3,
        num_hierarchies=3,block_repeats=depths,num_classes=3,gamma=gamma)
    report['parameter_count']=sum(p.numel() for p in model.parameters())
    report['limitations'].append('Depths and gamma inferred from checkpoint, not original training provenance.')
model.load_state_dict(state, strict=True)
report['checked_weight'] = weight.name
report['strict_load_seconds'] = time.perf_counter()-t0
model.eval()
with torch.inference_mode():
    sample = torch.zeros(1,4,3,28,28)
    t0 = time.perf_counter()
    result = model(sample)
    report['synthetic_cpu_seconds']=time.perf_counter()-t0
    report['output_shape']=list(result.shape)
    report['finite_output']=bool(torch.isfinite(result).all())
    report['synthetic_logits']=result.tolist()
inventory=[]
reference_shapes={k:tuple(v.shape) for k,v in state.items()}
for file in weights:
    candidate=torch.load(file,map_location='cpu',weights_only=True,mmap=True)
    candidate_depths=tuple(max(int(k.split('.')[4]) for k in candidate if k.startswith(f'layers.{level}.0.layers.'))+1 for level in range(3))
    inventory.append({'file':file.name,'depths':candidate_depths,
        'gamma_values': sorted(set(round(-float(v[3,0]),6) for k,v in candidate.items() if k.endswith('P_matrix'))),
        'same_keys_and_shapes_as_first': {k:tuple(v.shape) for k,v in candidate.items()}==reference_shapes})
    del candidate
report['checkpoint_inventory']=inventory
report['sha256']=hashlib.file_digest(weight.open('rb'), 'sha256').hexdigest()
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
