import 'package:flutter/material.dart';
import 'package:mesh_rescue/app/theme.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  static const _slides = <({IconData icon, Color color, String title, String body})>[
    (
      icon: Icons.cell_tower,
      color: MeshColors.primaryBlue,
      title: 'Zero-Infrastructure Mesh',
      body:
          'When cell towers and Wi-Fi fail, MeshRescue links nearby Android phones over Bluetooth and Wi-Fi Direct to pass alerts hop-by-hop.',
    ),
    (
      icon: Icons.verified_user,
      color: MeshColors.verifiedGreen,
      title: 'Cryptographically Verified Shelters',
      body:
          'Every message is Ed25519-signed. Only shelters signed by trusted responder keys show a green Verified Responder shield.',
    ),
    (
      icon: Icons.sos,
      color: MeshColors.sosRed,
      title: 'Hold 2s for SOS & Keep Radios On',
      body:
          'Hold the red SOS button for 2 seconds to broadcast your location. Next, grant Bluetooth, Nearby Wi-Fi, and Precise Location so the mesh can run.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to MeshRescue'),
        actions: [
          TextButton(
            onPressed: widget.onComplete,
            child: const Text('Skip', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(slide.icon, size: 88, color: slide.color),
                        const SizedBox(height: 24),
                        Text(
                          slide.title,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          slide.body,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 24 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? MeshColors.primaryBlue
                          : MeshColors.borderStrong,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(_page == _slides.length - 1 ? 'Get Started' : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

