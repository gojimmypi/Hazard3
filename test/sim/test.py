#!/usr/bin/env python3

import os
import shlex
import subprocess
import sys
import time
import yaml

MAKE = "make"

cfg = yaml.safe_load(open("test.yml"))

def run_and_wait(job_list):
	wait_procs = []
	for name, cmdline in job_list:
		wait_procs.append((name, subprocess.Popen(cmdline, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)))

	currtime = time.time()
	coinflip = False
	while True:
		# Dirty polling loop so we get a heartbeat indicator
		time.sleep(0.01)
		in_progress = []
		for name, proc in wait_procs:
			if proc.poll() is None:
				in_progress.append(name)
		if time.time() - currtime > 1:
			currtime = time.time()
			coinflip = not coinflip
			coinflip_char = "/\\"[coinflip]
			if len(in_progress) > 3:
				print(f"{coinflip_char} Waiting for {len(in_progress)} jobs to finish...")
			elif len(in_progress) > 0:
				print(f"{coinflip_char} Waiting for {', '.join(in_progress)} to finish...")
		if len(in_progress) == 0:
			break

	any_failed = False
	for name, proc in wait_procs:
		print(f"  {name:<40} : {'PASS' if proc.returncode == 0 else 'FAIL'}")
		if proc.returncode != 0:
			any_failed = True
			print("\n", proc.stderr.read().decode("utf-8"), "\n")
	return any_failed

print("Quick lint check...")
lint_configs =  ["default", "min", "min_debug"]
lint_jobs = [(cfg, ["make", "-C", "tb_cxxrtl", f"CONFIG={cfg}", "lint"]) for cfg in lint_configs]
if run_and_wait(lint_jobs):
	sys.exit("Lint failed.")

print("Building simulators...")
sim_build_jobs = []
for k in cfg["simulators"]:
	print(f"Starting build for {k}")
	sim_cfg = cfg["simulators"][k]
	cmdline = [MAKE, "-C", sim_cfg["make_dir"], *shlex.split(sim_cfg["make_args"])]
	sim_build_jobs.append((k, cmdline))

if run_and_wait(sim_build_jobs):
	sys.exit("Failed to build simulators.")

# For now, just run the sw_testcases tests on all simulators

for k in cfg["simulators"]:
	sim_cfg = cfg["simulators"][k]
	print(f"\nRunning sw_testcases on simulator {k}...\n")
	cmdline = [
		"./runtests",
		f"--tb=../{sim_cfg['exec']}",
		f"--march={sim_cfg['march']}",
		f"--build-dir={k}",
		"--no-tb-build"
	]
	if "tests" in sim_cfg:
		testlist = sim_cfg["tests"]
	elif "excluded_tests" in sim_cfg:
		testlist = []
		for path in os.listdir("sw_testcases"):
			excluded = path[:-2] in sim_cfg["excluded_tests"]
			if not excluded and path.endswith(".c"):
				testlist.append(path[:-2])
	else:
		testlist = []
	cmdline.extend(testlist)

	result = subprocess.run(cmdline, cwd="sw_testcases")

