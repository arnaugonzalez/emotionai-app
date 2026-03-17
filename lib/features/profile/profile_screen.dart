import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:emotion_ai/features/auth/auth_provider.dart';
import 'package:emotion_ai/features/auth/pin_code_screen.dart';
import 'package:emotion_ai/core/theme/app_theme.dart';
import 'package:emotion_ai/data/services/profile_service.dart';
import '../terms/terms_dialog.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  String? _selectedGender;
  final _jobController = TextEditingController();
  final _countryController = TextEditingController();
  String? _selectedPersonalityType;
  String? _selectedRelaxationTime;
  String? _selectedSelfcareFrequency;
  List<String> _selectedRelaxationTools = [];
  bool? _hasPreviousMentalHealthAppExperience;
  String? _selectedTherapyChatHistoryPreference;
  bool _isLoading = false;
  bool _hasAcceptedTerms = false;
  bool _hasPinCode = false;

  // Profile service
  final ProfileService _profileService = ProfileService();

  final List<String> _personalityTypes = [
    'INTJ',
    'INTP',
    'ENTJ',
    'ENTP',
    'INFJ',
    'INFP',
    'ENFJ',
    'ENFP',
    'ISTJ',
    'ISFJ',
    'ESTJ',
    'ESFJ',
    'ISTP',
    'ISFP',
    'ESTP',
    'ESFP',
    'Not Sure',
  ];

  final List<String> _relaxationTimeOptions = [
    'Morning',
    'Afternoon',
    'Evening',
    'Night',
    'Various times',
  ];

  final List<String> _selfcareFrequencyOptions = [
    'Multiple times a day',
    'Once a day',
    'Multiple times a week',
    'Once a week',
    'Rarely',
    'Almost never',
  ];

  final List<String> _relaxationToolOptions = [
    'Breathing exercises',
    'Binaural sounds',
    'Chatbot therapy',
    'Emotional calendar',
    'Meditation',
    'Exercise',
    'Reading',
    'Nature walks',
    'Music',
    'Creative activities',
  ];

  final List<String> _therapyChatHistoryOptions = [
    'Last week',
    'Last month',
    'No history needed',
  ];

  @override
  void initState() {
    super.initState();
    _loadPinStatus();
    _loadExistingProfile();
  }

  Future<void> _loadPinStatus() async {
    const secureStorage = FlutterSecureStorage();
    final pinHash = await secureStorage.read(key: 'user_pin_hash');
    setState(() {
      _hasPinCode = pinHash != null;
    });
  }

  Future<void> _loadExistingProfile() async {
    try {
      final profile = await _profileService.getUserProfile();
      if (profile != null) {
        setState(() {
          _nameController.text = profile.firstName ?? '';
          _ageController.text =
              profile.dateOfBirth != null
                  ? (DateTime.now().difference(profile.dateOfBirth!).inDays ~/
                          365)
                      .toString()
                  : '';
          _jobController.text = profile.occupation ?? '';
          _countryController.text = ''; // Country not in current profile model

          // Load additional preferences from user_profile_data if available
          if (profile.userProfileData != null) {
            final userData = profile.userProfileData!;
            _selectedPersonalityType = userData['personality_type'];
            _selectedRelaxationTime = userData['relaxation_time'];
            _selectedSelfcareFrequency = userData['selfcare_frequency'];
            _selectedRelaxationTools = List<String>.from(
              userData['relaxation_tools'] ?? [],
            );
            _hasPreviousMentalHealthAppExperience =
                userData['has_previous_mental_health_app_experience'];
            _selectedTherapyChatHistoryPreference =
                userData['therapy_chat_history_preference'];
            _countryController.text = userData['country'] ?? '';
            _selectedGender = userData['gender'];
          }
        });
      }
    } catch (e) {
      // Profile not found or error loading - this is normal for new users
      print('No existing profile found: $e');
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Calculate date of birth from age
      DateTime? dateOfBirth;
      if (_ageController.text.isNotEmpty) {
        final age = int.tryParse(_ageController.text);
        if (age != null) {
          dateOfBirth = DateTime.now().subtract(Duration(days: age * 365));
        }
      }

      // Prepare profile data
      final profileData = {
        'first_name': _nameController.text,
        'last_name': '', // Not collected in current form
        'date_of_birth': dateOfBirth?.toIso8601String(),
        'occupation': _jobController.text,
        'phone_number': '', // Not collected in current form
        'address': '', // Not collected in current form
        'emergency_contact': null, // Not collected in current form
        'medical_info': null, // Not collected in current form
        'therapy_preferences': {
          'communication_style': _selectedPersonalityType,
          'session_frequency': _selectedSelfcareFrequency,
          'focus_areas': _selectedRelaxationTools,
          'goals': '', // Not collected in current form
        },
        // Store additional preferences in user_profile_data for future use
        'user_profile_data': {
          'personality_type': _selectedPersonalityType,
          'relaxation_time': _selectedRelaxationTime,
          'selfcare_frequency': _selectedSelfcareFrequency,
          'relaxation_tools': _selectedRelaxationTools,
          'has_previous_mental_health_app_experience':
              _hasPreviousMentalHealthAppExperience,
          'therapy_chat_history_preference':
              _selectedTherapyChatHistoryPreference,
          'country': _countryController.text,
          'gender': _selectedGender,
        },
      };

      await _profileService.createOrUpdateProfile(profileData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _setupPinCode() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const PinCodeScreen(isSettingUp: true),
      ),
    );

    if (result == true) {
      setState(() {
        _hasPinCode = true;
      });
    }
  }

  Future<void> _launchPersonalityTestUrl() async {
    final uri = Uri.parse(
      'https://www.16personalities.com/free-personality-test',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open personality test website'),
          ),
        );
      }
    }
  }

  Future<void> _showTermsDialog() async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => TermsDialog(
            onAccept: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('has_accepted_terms', true);
              if (!mounted) return;
              setState(() {
                _hasAcceptedTerms = true;
              });
              Navigator.of(context).pop();
            },
            onCancel: () {
              Navigator.of(context).pop();
            },
          ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _jobController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.backgroundDecoration,
        child: SafeArea(
          child: Column(
            children: [
              // Custom AppBar with gradient
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: AppTheme.onPrimary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Expanded(
                      child: Text(
                        'Profile Settings',
                        style: Theme.of(
                          context,
                        ).textTheme.headlineMedium?.copyWith(
                          color: AppTheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(width: 48), // Balance the back button
                  ],
                ),
              ),

              // Scrollable content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Basic Information Card
                          Container(
                            decoration: AppTheme.cardDecoration,
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: AppTheme.accentGradient,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.person,
                                        color: AppTheme.onPrimary,
                                        size: 24,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Basic Information',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineMedium?.copyWith(
                                        color: AppTheme.primaryViolet,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 20),
                                TextFormField(
                                  controller: _nameController,
                                  decoration: InputDecoration(
                                    labelText: 'Name',
                                    prefixIcon: Icon(Icons.person_outline),
                                    hintText: 'Enter your full name',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your name';
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _ageController,
                                        decoration: InputDecoration(
                                          labelText: 'Age',
                                          prefixIcon: Icon(Icons.cake_outlined),
                                          hintText: 'Your age',
                                        ),
                                        keyboardType: TextInputType.number,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your age';
                                          }
                                          if (int.tryParse(value) == null) {
                                            return 'Please enter a valid number';
                                          }
                                          return null;
                                        },
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _selectedGender,
                                        decoration: InputDecoration(
                                          labelText: 'Gender',
                                          prefixIcon: Icon(
                                            Icons.person_pin_outlined,
                                          ),
                                        ),
                                        items:
                                            [
                                              'Male',
                                              'Female',
                                              'Non-binary',
                                              'Prefer not to say',
                                            ].map((String gender) {
                                              return DropdownMenuItem<String>(
                                                value: gender,
                                                child: Text(
                                                  gender,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              );
                                            }).toList(),
                                        onChanged: (String? newValue) {
                                          setState(() {
                                            _selectedGender = newValue;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16),
                                TextFormField(
                                  controller: _jobController,
                                  decoration: InputDecoration(
                                    labelText: 'Occupation',
                                    prefixIcon: Icon(Icons.work_outline),
                                    hintText: 'Your job or profession',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your occupation';
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: 16),
                                TextFormField(
                                  controller: _countryController,
                                  decoration: InputDecoration(
                                    labelText: 'Country',
                                    prefixIcon: Icon(
                                      Icons.location_on_outlined,
                                    ),
                                    hintText: 'Where are you located?',
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your country';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 24),

                          // Preferences Card
                          Container(
                            decoration: AppTheme.cardDecoration,
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: AppTheme.accentGradient,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.tune,
                                        color: AppTheme.onPrimary,
                                        size: 24,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Wellness Preferences',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineMedium?.copyWith(
                                        color: AppTheme.primaryViolet,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 20),

                                // Personality Type field with help icon
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<String>(
                                        value: _selectedPersonalityType,
                                        decoration: InputDecoration(
                                          labelText: '16 Personality Type',
                                          prefixIcon: Icon(
                                            Icons.psychology_outlined,
                                          ),
                                          helperText:
                                              'Select your MBTI personality type',
                                        ),
                                        items:
                                            _personalityTypes.map((
                                              String type,
                                            ) {
                                              return DropdownMenuItem<String>(
                                                value: type,
                                                child: Text(
                                                  type,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              );
                                            }).toList(),
                                        onChanged: (String? newValue) {
                                          setState(() {
                                            _selectedPersonalityType = newValue;
                                          });
                                        },
                                      ),
                                    ),
                                    Container(
                                      margin: EdgeInsets.only(left: 8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.lightViolet,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.help_outline,
                                          color: AppTheme.primaryViolet,
                                        ),
                                        tooltip:
                                            'Learn about personality types',
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder:
                                                (context) => AlertDialog(
                                                  title: Text(
                                                    '16 Personality Types',
                                                    style: TextStyle(
                                                      color:
                                                          AppTheme
                                                              .primaryViolet,
                                                    ),
                                                  ),
                                                  content: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Text(
                                                        'The 16 personality types test tells you which celebrities you\'re most like! It\'s a popular psychology framework to understand different personality traits.',
                                                        style:
                                                            Theme.of(context)
                                                                .textTheme
                                                                .bodyMedium,
                                                      ),
                                                      SizedBox(height: 16),
                                                      Container(
                                                        decoration:
                                                            AppTheme
                                                                .primaryGradientDecoration,
                                                        child: TextButton.icon(
                                                          icon: Icon(
                                                            Icons.open_in_new,
                                                            color:
                                                                AppTheme
                                                                    .onPrimary,
                                                          ),
                                                          label: Text(
                                                            'Take the test here, it\'s free!',
                                                            style: TextStyle(
                                                              color:
                                                                  AppTheme
                                                                      .onPrimary,
                                                            ),
                                                          ),
                                                          onPressed:
                                                              _launchPersonalityTestUrl,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed:
                                                          () =>
                                                              Navigator.of(
                                                                context,
                                                              ).pop(),
                                                      child: Text('Close'),
                                                    ),
                                                  ],
                                                ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16),

                                // Relaxation time preference
                                DropdownButtonFormField<String>(
                                  value: _selectedRelaxationTime,
                                  decoration: InputDecoration(
                                    labelText:
                                        'What time of day do you tend to relax?',
                                    prefixIcon: Icon(Icons.access_time),
                                  ),
                                  items:
                                      _relaxationTimeOptions.map((String time) {
                                        return DropdownMenuItem<String>(
                                          value: time,
                                          child: Text(time),
                                        );
                                      }).toList(),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _selectedRelaxationTime = newValue;
                                    });
                                  },
                                ),
                                SizedBox(height: 16),

                                // Self-care frequency
                                DropdownButtonFormField<String>(
                                  value: _selectedSelfcareFrequency,
                                  decoration: InputDecoration(
                                    labelText:
                                        'How often do you take time for yourself?',
                                    prefixIcon: Icon(Icons.self_improvement),
                                  ),
                                  items:
                                      _selfcareFrequencyOptions.map((
                                        String frequency,
                                      ) {
                                        return DropdownMenuItem<String>(
                                          value: frequency,
                                          child: Text(frequency),
                                        );
                                      }).toList(),
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      _selectedSelfcareFrequency = newValue;
                                    });
                                  },
                                ),
                                SizedBox(height: 20),

                                // Relaxation tools
                                Text(
                                  'What tools help you relax? (Select all that apply)',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.copyWith(
                                    color: AppTheme.primaryViolet,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 12),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children:
                                      _relaxationToolOptions.map((tool) {
                                        final isSelected =
                                            _selectedRelaxationTools.contains(
                                              tool,
                                            );
                                        return FilterChip(
                                          label: Text(
                                            tool,
                                            style: TextStyle(
                                              color:
                                                  isSelected
                                                      ? AppTheme.onPrimary
                                                      : AppTheme.onSurface,
                                              fontWeight:
                                                  isSelected
                                                      ? FontWeight.w600
                                                      : FontWeight.normal,
                                            ),
                                          ),
                                          selected: isSelected,
                                          selectedColor: AppTheme.primaryViolet,
                                          backgroundColor:
                                              AppTheme.surfaceVariant,
                                          checkmarkColor: AppTheme.onPrimary,
                                          onSelected: (selected) {
                                            setState(() {
                                              if (selected) {
                                                _selectedRelaxationTools.add(
                                                  tool,
                                                );
                                              } else {
                                                _selectedRelaxationTools.remove(
                                                  tool,
                                                );
                                              }
                                            });
                                          },
                                        );
                                      }).toList(),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 24),

                          // Experience and Preferences Card
                          Container(
                            decoration: AppTheme.cardDecoration,
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: AppTheme.accentGradient,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.psychology,
                                        color: AppTheme.onPrimary,
                                        size: 24,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Experience & Preferences',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineMedium?.copyWith(
                                        color: AppTheme.primaryViolet,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 20),

                                // Previous mental health app experience
                                Text(
                                  'Have you ever used a mental health app before?',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.copyWith(
                                    color: AppTheme.primaryViolet,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: RadioListTile<bool>(
                                        title: Text('Yes'),
                                        value: true,
                                        groupValue:
                                            _hasPreviousMentalHealthAppExperience,
                                        activeColor: AppTheme.primaryViolet,
                                        onChanged: (value) {
                                          setState(() {
                                            _hasPreviousMentalHealthAppExperience =
                                                value;
                                          });
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      child: RadioListTile<bool>(
                                        title: Text('No'),
                                        value: false,
                                        groupValue:
                                            _hasPreviousMentalHealthAppExperience,
                                        activeColor: AppTheme.primaryViolet,
                                        onChanged: (value) {
                                          setState(() {
                                            _hasPreviousMentalHealthAppExperience =
                                                value;
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 16),

                                // Therapy chat history preference
                                Text(
                                  'For AI therapy conversations, what context would you prefer?',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.copyWith(
                                    color: AppTheme.primaryViolet,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Column(
                                  children:
                                      _therapyChatHistoryOptions.map((option) {
                                        return RadioListTile<String>(
                                          title: Text(option),
                                          value: option,
                                          groupValue:
                                              _selectedTherapyChatHistoryPreference,
                                          activeColor: AppTheme.primaryViolet,
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedTherapyChatHistoryPreference =
                                                  value;
                                            });
                                          },
                                        );
                                      }).toList(),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 24),

                          // Security & Terms Card
                          Container(
                            decoration: AppTheme.cardDecoration,
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        gradient: AppTheme.accentGradient,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.security,
                                        color: AppTheme.onPrimary,
                                        size: 24,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Security & Terms',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineMedium?.copyWith(
                                        color: AppTheme.primaryViolet,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 20),

                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.description_outlined,
                                    color: AppTheme.primaryViolet,
                                  ),
                                  title: Text(
                                    'Terms and Conditions',
                                    style: TextStyle(
                                      color: AppTheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _hasAcceptedTerms
                                        ? 'Accepted'
                                        : 'Please accept the terms and conditions',
                                    style: TextStyle(
                                      color:
                                          _hasAcceptedTerms
                                              ? AppTheme.primaryViolet
                                              : AppTheme.primaryRed,
                                    ),
                                  ),
                                  trailing: Icon(
                                    _hasAcceptedTerms
                                        ? Icons.check_circle
                                        : Icons.arrow_forward,
                                    color:
                                        _hasAcceptedTerms
                                            ? AppTheme.primaryViolet
                                            : AppTheme.onSurfaceVariant,
                                  ),
                                  onTap: _showTermsDialog,
                                ),
                                Divider(
                                  color: AppTheme.lightViolet.withOpacity(0.3),
                                ),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    Icons.lock_outline,
                                    color: AppTheme.primaryViolet,
                                  ),
                                  title: Text(
                                    'PIN Code',
                                    style: TextStyle(
                                      color: AppTheme.onSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _hasPinCode
                                        ? 'Set up and secured'
                                        : 'Please set up a PIN code for security',
                                    style: TextStyle(
                                      color:
                                          _hasPinCode
                                              ? AppTheme.primaryViolet
                                              : AppTheme.primaryRed,
                                    ),
                                  ),
                                  trailing: Icon(
                                    _hasPinCode
                                        ? Icons.check_circle
                                        : Icons.arrow_forward,
                                    color:
                                        _hasPinCode
                                            ? AppTheme.primaryViolet
                                            : AppTheme.onSurfaceVariant,
                                  ),
                                  onTap: _setupPinCode,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 32),

                          // Action Buttons
                          Column(
                            children: [
                              Container(
                                width: double.infinity,
                                height: 56,
                                decoration: AppTheme.primaryGradientDecoration,
                                child: ElevatedButton(
                                  onPressed: _isLoading ? null : _saveProfile,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child:
                                      _isLoading
                                          ? SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: CircularProgressIndicator(
                                              color: AppTheme.onPrimary,
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.save,
                                                color: AppTheme.onPrimary,
                                              ),
                                              SizedBox(width: 8),
                                              Text(
                                                'Save Profile',
                                                style: TextStyle(
                                                  color: AppTheme.onPrimary,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                ),
                              ),
                              SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: OutlinedButton(
                                  onPressed:
                                      () =>
                                          ref
                                              .read(authProvider.notifier)
                                              .logout(),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: AppTheme.primaryRed,
                                      width: 2,
                                    ),
                                    foregroundColor: AppTheme.primaryRed,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.logout,
                                        color: AppTheme.primaryRed,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Logout',
                                        style: TextStyle(
                                          color: AppTheme.primaryRed,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
